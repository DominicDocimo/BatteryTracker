//
//  BatteryStatusViewModel.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/17/26.
//

import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class BatteryStatusViewModel {
    var cycleCount: Int?
    var rawBatteryHealthPercent: String = "Unknown"
    var officialBatteryHealthText: String = "Unknown"
    var officialBatteryHealthPercent: Int?
    var currentCapacityMah: Int?
    var maxCapacityMah: Int?
    var designCapacityMah: Int?
    var cyclesToday: Int?
    var cyclesPerDayNeeded: Double?
    var mahToNextCycle: Int?
    var timeRemainingText: String = "—"
    var storeLocationMessage: String?

    private enum DefaultsKeys {
        static let cyclesBaselineDate = "cyclesBaselineDate"
        static let cyclesBaselineCount = "cyclesBaselineCount"
        static let lastCapacityMah = "lastCapacityMah"
        static let lastCapacityMahForUsage = "lastCapacityMahForUsage"
        static let lastCapacityMahForCycle = "lastCapacityMahForCycle"
        static let lastCycleCount = "lastCycleCount"
        static let dischargedSinceLastCycleMah = "dischargedSinceLastCycleMah"
        static let lastSampleDateKey = "lastSampleDateKey"
        static let lastSampleTimestamp = "lastSampleTimestamp"
        static let lastPowerSourceState = "lastPowerSourceState"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func updateBatteryInfo(modelContext: ModelContext) {
        cycleCount = getBatteryCycleCount()
        rawBatteryHealthPercent = getBatteryHealthText() ?? "Unknown"
        officialBatteryHealthText = getOfficialBatteryHealthText() ?? "Unknown"

        if let capacity = getBatteryCapacityMah() {
            currentCapacityMah = capacity.current
            maxCapacityMah = capacity.max
        } else {
            currentCapacityMah = nil
            maxCapacityMah = nil
        }

        designCapacityMah = getBatteryDesignCapacityMah()
        let todayDate = Calendar.current.startOfDay(for: Date())
        updateCyclesToday(modelContext: modelContext, todayDate: todayDate)
        updateCyclesPerDayNeeded()
        updateMahToNextCycle()
        updateTimeRemaining()
        updateDailyStats(modelContext: modelContext, todayDate: todayDate)
    }

    func refreshIntervalSeconds() -> Double {
        let isHistoryVisible = UserDefaults.standard.bool(forKey: "historyVisible")
        return isHistoryVisible ? 1.0 : 5.0
    }

    func refreshOfficialBatteryHealthPercent() async {
        let percent = await getOfficialBatteryHealthPercent()
        officialBatteryHealthPercent = percent
    }

    func updateCyclesToday(modelContext: ModelContext, todayDate: Date) {
        guard let cycleCount else {
            cyclesToday = nil
            return
        }

        let defaults = UserDefaults.standard
        let todayKey = Self.dayFormatter.string(from: Date())
        let baselineDate = defaults.string(forKey: DefaultsKeys.cyclesBaselineDate)
        let existing = fetchDailyCycle(for: todayDate, modelContext: modelContext)

        if baselineDate != todayKey {
            let existingCycles = existing?.cycles ?? 0
            let baseline = max(0, cycleCount - existingCycles)
            defaults.set(todayKey, forKey: DefaultsKeys.cyclesBaselineDate)
            defaults.set(baseline, forKey: DefaultsKeys.cyclesBaselineCount)
            cyclesToday = existingCycles
            upsertDailyCycle(
                for: todayDate,
                modelContext: modelContext,
                existing: existing
            ) { daily in
                daily.cycles = existingCycles
            }
            try? modelContext.save()
            return
        }

        let storedBaseline = defaults.object(forKey: DefaultsKeys.cyclesBaselineCount) as? Int ?? cycleCount
        let existingCycles = existing?.cycles ?? 0

        if storedBaseline == 0,
           existingCycles > 0,
           existingCycles < cycleCount {
            let correctedBaseline = max(0, cycleCount - existingCycles)
            defaults.set(correctedBaseline, forKey: DefaultsKeys.cyclesBaselineCount)
        }

        let baseline = defaults.object(forKey: DefaultsKeys.cyclesBaselineCount) as? Int ?? cycleCount
        let todayCycles = max(0, cycleCount - baseline)

        cyclesToday = todayCycles
        upsertDailyCycle(
            for: todayDate,
            modelContext: modelContext,
            existing: existing
        ) { daily in
            daily.cycles = todayCycles
        }
        try? modelContext.save()
    }

    func updateCyclesPerDayNeeded() {
        guard let cycleCount else {
            cyclesPerDayNeeded = nil
            return
        }

        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 1

        guard let targetDate = Calendar.current.date(from: components) else {
            cyclesPerDayNeeded = nil
            return
        }

        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0
        guard daysRemaining > 0 else {
            cyclesPerDayNeeded = nil
            return
        }

        let remainingCycles = max(0, 1000 - cycleCount)
        cyclesPerDayNeeded = Double(remainingCycles) / Double(daysRemaining)
    }

    func updateMahToNextCycle() {
        guard let currentCapacityMah,
              let maxCapacityMah,
              maxCapacityMah > 0 else {
            mahToNextCycle = nil
            return
        }

        let defaults = UserDefaults.standard
        let lastCapacity = defaults.object(forKey: DefaultsKeys.lastCapacityMahForCycle) as? Int
        let lastCycle = defaults.object(forKey: DefaultsKeys.lastCycleCount) as? Int
        var discharged = defaults.double(forKey: DefaultsKeys.dischargedSinceLastCycleMah)

        let didIncrementCycle = cycleCount.map { current in
            lastCycle.map { current > $0 } ?? false
        } ?? false

        if didIncrementCycle {
            discharged = 0
            defaults.set(currentCapacityMah, forKey: DefaultsKeys.lastCapacityMahForCycle)
        } else if let lastCapacity, currentCapacityMah < lastCapacity {
            discharged += Double(lastCapacity - currentCapacityMah)
        }

        defaults.set(currentCapacityMah, forKey: DefaultsKeys.lastCapacityMahForCycle)
        if let cycleCount {
            defaults.set(cycleCount, forKey: DefaultsKeys.lastCycleCount)
        }
        defaults.set(discharged, forKey: DefaultsKeys.dischargedSinceLastCycleMah)

        let remaining = max(0.0, Double(maxCapacityMah) - discharged)
        mahToNextCycle = Int(ceil(remaining))
    }
    private func updateTimeRemaining() {
        guard let remaining = getBatteryTimeRemaining() else {
            timeRemainingText = "—"
            return
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        let formatted = formatter.string(from: TimeInterval(remaining.minutes * 60)) ?? "—"
        timeRemainingText = remaining.isCharging
            ? "Time to Full: \(formatted)"
            : "Time to Empty: \(formatted)"
    }

    func updateDailyStats(modelContext: ModelContext, todayDate: Date) {
        let defaults = UserDefaults.standard
        let todayKey = Self.dayFormatter.string(from: Date())
        let lastSampleDateKey = defaults.string(forKey: DefaultsKeys.lastSampleDateKey)
        let lastSampleTimestamp = defaults.double(forKey: DefaultsKeys.lastSampleTimestamp)
        let lastPowerStateRaw = defaults.string(forKey: DefaultsKeys.lastPowerSourceState)
        let lastPowerState = PowerSourceState(rawValue: lastPowerStateRaw ?? "") ?? .unknown

        let now = Date()
        let currentPowerState = getPowerSourceState()

        guard lastSampleTimestamp > 0, lastSampleDateKey == todayKey else {
            if let currentCapacityMah {
                defaults.set(currentCapacityMah, forKey: DefaultsKeys.lastCapacityMahForUsage)
            }
            defaults.set(todayKey, forKey: DefaultsKeys.lastSampleDateKey)
            defaults.set(now.timeIntervalSince1970, forKey: DefaultsKeys.lastSampleTimestamp)
            defaults.set(currentPowerState.rawValue, forKey: DefaultsKeys.lastPowerSourceState)
            return
        }

        let elapsed = max(0, now.timeIntervalSince1970 - lastSampleTimestamp)
        let effectiveState = lastPowerState == .unknown ? currentPowerState : lastPowerState

        guard effectiveState != .unknown else {
            defaults.set(todayKey, forKey: DefaultsKeys.lastSampleDateKey)
            defaults.set(now.timeIntervalSince1970, forKey: DefaultsKeys.lastSampleTimestamp)
            defaults.set(currentPowerState.rawValue, forKey: DefaultsKeys.lastPowerSourceState)
            return
        }

        let existing = fetchDailyCycle(for: todayDate, modelContext: modelContext)
        let totalMahUsed = updateMahUsed(existing: existing)
        let timeOnBattery = (existing?.timeOnBattery ?? 0) + (effectiveState == .battery ? elapsed : 0)
        let timePluggedIn = (existing?.timePluggedIn ?? 0) + (effectiveState == .ac ? elapsed : 0)
        let rawCycles = calculateRawCycles(totalMahUsed: totalMahUsed)

        upsertDailyCycle(
            for: todayDate,
            modelContext: modelContext,
            existing: existing
        ) { daily in
            daily.totalMahUsed = totalMahUsed
            daily.timeOnBattery = timeOnBattery
            daily.timePluggedIn = timePluggedIn
            daily.rawCycles = rawCycles
        }

        defaults.set(todayKey, forKey: DefaultsKeys.lastSampleDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: DefaultsKeys.lastSampleTimestamp)
        defaults.set(currentPowerState.rawValue, forKey: DefaultsKeys.lastPowerSourceState)
    }

    private func updateMahUsed(existing: DailyCycle?) -> Double {
        guard let currentCapacityMah else {
            return existing?.totalMahUsed ?? 0
        }

        let defaults = UserDefaults.standard
        let lastCapacity = defaults.object(forKey: DefaultsKeys.lastCapacityMahForUsage) as? Int
        let previousTotal = existing?.totalMahUsed ?? 0

        defer {
            defaults.set(currentCapacityMah, forKey: DefaultsKeys.lastCapacityMahForUsage)
        }

        guard let lastCapacity, currentCapacityMah < lastCapacity else {
            return previousTotal
        }

        let delta = Double(lastCapacity - currentCapacityMah)
        return previousTotal + max(0, delta)
    }

    private func calculateRawCycles(totalMahUsed: Double) -> Double {
        guard let maxCapacityMah, maxCapacityMah > 0 else {
            return 0
        }

        return totalMahUsed / Double(maxCapacityMah)
    }

    func revealStoreLocation(modelContext: ModelContext) {
        guard let url = modelContext.container.configurations.first?.url else {
            storeLocationMessage = "No on-disk store URL available."
            return
        }

        let path = url.path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        storeLocationMessage = "Path copied to clipboard:\n\(path)"
    }

    func formatDecimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func fetchDailyCycle(for date: Date, modelContext: ModelContext) -> DailyCycle? {
        let descriptor = FetchDescriptor<DailyCycle>(
            predicate: #Predicate { $0.date == date }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func upsertDailyCycle(
        for date: Date,
        modelContext: ModelContext,
        existing: DailyCycle?,
        update: (DailyCycle) -> Void
    ) {
        if let existing {
            update(existing)
        } else {
            let daily = DailyCycle(date: date, cycles: 0)
            update(daily)
            modelContext.insert(daily)
        }
    }
}
