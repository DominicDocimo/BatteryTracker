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
    var timeRemainingText: String = "Time to Full/Empty: —"
    var timeToTenMinutesRemainingText: String = "Time to 10% Left: —"
    var timeToNextCycleText: String = "Time Until Next Cycle: —"
    var storeLocationMessage: String?
    var currentPowerSourceState: PowerSourceState = .unknown
    var totalMahUsedToday: Double?
    private var lastTimeToNextCycleValue: String?

    private enum DefaultsKeys {
        static let cyclesBaselineDate = "cyclesBaselineDate"
        static let cyclesBaselineCount = "cyclesBaselineCount"
        static let lastCapacityMah = "lastCapacityMah"
        static let lastCapacityMahForUsage = "lastCapacityMahForUsage"
        static let lastCapacityMahForCycle = "lastCapacityMahForCycle"
        static let lastCycleCount = "lastCycleCount"
        static let dischargedSinceLastCycleMah = "dischargedSinceLastCycleMah"
        static let cycleMahUsedDayKey = "cycleMahUsedDayKey"
        static let cycleMahUsedToday = "cycleMahUsedToday"
        static let cycleStartedPreviousDay = "cycleStartedPreviousDay"
        static let lastSampleDateKey = "lastSampleDateKey"
        static let lastSampleTimestamp = "lastSampleTimestamp"
        static let lastPowerSourceState = "lastPowerSourceState"
        static let todayMahUsed = "todayMahUsed"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func updateBatteryInfo(modelContext: ModelContext) {
        currentPowerSourceState = getPowerSourceState()
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
        updateMahToNextCycle(modelContext: modelContext, todayDate: todayDate)
        updateTimeRemaining()
        updateTimeToNextCycle(modelContext: modelContext, todayDate: todayDate)
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

    func updateMahToNextCycle(modelContext: ModelContext, todayDate: Date) {
        guard let currentCapacityMah,
              let designCapacityMah,
              designCapacityMah > 0 else {
            mahToNextCycle = nil
            return
        }

        let defaults = UserDefaults.standard
        let todayKey = Self.dayFormatter.string(from: Date())
        let storedDayKey = defaults.string(forKey: DefaultsKeys.cycleMahUsedDayKey)
        var cycleMahUsedToday = defaults.double(forKey: DefaultsKeys.cycleMahUsedToday)
        var cycleStartedPreviousDay = defaults.bool(forKey: DefaultsKeys.cycleStartedPreviousDay)

        if storedDayKey != todayKey {
            if let storedDayKey,
               let previousDate = Self.dayFormatter.date(from: storedDayKey),
               cycleMahUsedToday > 0 {
                appendCycleBreakdown(
                    for: previousDate,
                    modelContext: modelContext,
                    mahUsed: cycleMahUsedToday,
                    designCapacityMah: designCapacityMah,
                    isPartial: true
                )
                cycleStartedPreviousDay = true
            }

            cycleMahUsedToday = 0
            defaults.set(todayKey, forKey: DefaultsKeys.cycleMahUsedDayKey)
        }

        let lastCapacity = defaults.object(forKey: DefaultsKeys.lastCapacityMahForCycle) as? Int
        let lastCycle = defaults.object(forKey: DefaultsKeys.lastCycleCount) as? Int
        var discharged = defaults.double(forKey: DefaultsKeys.dischargedSinceLastCycleMah)

        let didIncrementCycle = cycleCount.map { current in
            lastCycle.map { current > $0 } ?? false
        } ?? false

        if didIncrementCycle {
            if cycleMahUsedToday > 0 {
                appendCycleBreakdown(
                    for: todayDate,
                    modelContext: modelContext,
                    mahUsed: cycleMahUsedToday,
                    designCapacityMah: designCapacityMah,
                    isPartial: cycleStartedPreviousDay
                )
            }
            cycleMahUsedToday = 0
            cycleStartedPreviousDay = false
            discharged = 0
            defaults.set(currentCapacityMah, forKey: DefaultsKeys.lastCapacityMahForCycle)
        } else if let lastCapacity, currentCapacityMah < lastCapacity {
            let delta = Double(lastCapacity - currentCapacityMah)
            discharged += delta
            cycleMahUsedToday += delta
        }

        defaults.set(currentCapacityMah, forKey: DefaultsKeys.lastCapacityMahForCycle)
        if let cycleCount {
            defaults.set(cycleCount, forKey: DefaultsKeys.lastCycleCount)
        }
        defaults.set(discharged, forKey: DefaultsKeys.dischargedSinceLastCycleMah)
        defaults.set(cycleMahUsedToday, forKey: DefaultsKeys.cycleMahUsedToday)
        defaults.set(cycleStartedPreviousDay, forKey: DefaultsKeys.cycleStartedPreviousDay)

        let remaining = max(0.0, Double(designCapacityMah) - discharged)
        mahToNextCycle = Int(ceil(remaining))
    }

    private func appendCycleBreakdown(
        for date: Date,
        modelContext: ModelContext,
        mahUsed: Double,
        designCapacityMah: Int,
        isPartial: Bool
    ) {
        guard mahUsed > 0 else {
            return
        }

        let targetDate = Calendar.current.startOfDay(for: date)
        let completionPercent = min(100.0, max(0.0, (mahUsed / Double(designCapacityMah)) * 100.0))
        let breakdown = CycleBreakdown(
            index: nextCycleIndex(for: targetDate, modelContext: modelContext),
            mahUsed: mahUsed,
            isPartial: isPartial,
            completionPercent: completionPercent
        )

        if let existing = fetchDailyCycle(for: targetDate, modelContext: modelContext) {
            existing.cycleBreakdowns.append(breakdown)
        } else {
            let daily = DailyCycle(date: targetDate, cycles: 0)
            daily.cycleBreakdowns = [breakdown]
            modelContext.insert(daily)
        }

        try? modelContext.save()
    }

    private func nextCycleIndex(for date: Date, modelContext: ModelContext) -> Int {
        guard let existing = fetchDailyCycle(for: date, modelContext: modelContext) else {
            return 1
        }
        let maxIndex = existing.cycleBreakdowns.map(\.index).max() ?? 0
        return maxIndex + 1
    }
    private func updateTimeRemaining() {
        guard let remaining = getBatteryTimeRemaining() else {
            timeRemainingText = "Time to Full/Empty: —"
            timeToTenMinutesRemainingText = "Time to 10% Left: —"
            return
        }

        guard remaining.minutes > 0 else {
            timeRemainingText = "Time to Full/Empty: —"
            timeToTenMinutesRemainingText = "Time to 10% Left: —"
            return
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        let remainingSeconds = Double(remaining.minutes * 60)
        let formatted = formatter.string(from: TimeInterval(remainingSeconds)) ?? "—"
        if remaining.isCharging {
            timeRemainingText = appendReachTime(to: "Time to Full: \(formatted)", seconds: remainingSeconds)
            timeToTenMinutesRemainingText = "Time to 10% Left: —"
            return
        }

        timeRemainingText = appendReachTime(to: "Time to Empty: \(formatted)", seconds: remainingSeconds)
        guard let currentCapacityMah,
              let maxCapacityMah,
              currentCapacityMah > 0,
              maxCapacityMah > 0 else {
            timeToTenMinutesRemainingText = "Time to 10% Left: —"
            return
        }

        let targetMah = Double(maxCapacityMah) * 0.10
        let remainingToTen = Double(currentCapacityMah) - targetMah
        if remainingToTen > 0 {
            let minutesToTen = (remainingToTen / Double(currentCapacityMah)) * Double(remaining.minutes)
            let timeToTen = formatter.string(from: TimeInterval(minutesToTen * 60)) ?? "—"
            let secondsToTen = minutesToTen * 60
            timeToTenMinutesRemainingText = appendReachTime(
                to: "Time to 10% Left: \(timeToTen)",
                seconds: secondsToTen
            )
        } else {
            timeToTenMinutesRemainingText = "Time to 10% Left: —"
        }
    }

    private func updateTimeToNextCycle(modelContext: ModelContext, todayDate: Date) {
        let isPaused = currentPowerSourceState == .ac
        if isPaused, let lastTimeToNextCycleValue {
            timeToNextCycleText = "Time Until Next Cycle: \(lastTimeToNextCycleValue) (Paused)"
            return
        } else if isPaused {
            timeToNextCycleText = "Time Until Next Cycle: —"
            return
        }

        guard let mahToNextCycle,
              mahToNextCycle > 0 else {
            if let lastTimeToNextCycleValue {
                timeToNextCycleText = "Time Until Next Cycle: \(lastTimeToNextCycleValue) (Unpaused - Calculating)"
            } else {
                timeToNextCycleText = "Time Until Next Cycle: —"
            }
            return
        }

        if let today = fetchDailyCycle(for: todayDate, modelContext: modelContext),
           today.timeOnBattery > 0,
           today.totalMahUsed > 0 {
            let mahPerSecond = today.totalMahUsed / today.timeOnBattery
            if mahPerSecond > 0 {
                let secondsRemaining = Double(mahToNextCycle) / mahPerSecond
                let formatted = formatDuration(secondsRemaining)
                lastTimeToNextCycleValue = formatted
                timeToNextCycleText = appendReachTime(
                    to: "Time Until Next Cycle: \(formatted)",
                    seconds: secondsRemaining
                )
                return
            }
        }

        if let remaining = getBatteryTimeRemaining(),
           remaining.isCharging == false,
           let currentCapacityMah,
           remaining.minutes > 0,
           currentCapacityMah > 0 {
            let secondsToEmpty = Double(remaining.minutes * 60)
            let mahPerSecond = Double(currentCapacityMah) / secondsToEmpty
            if mahPerSecond > 0 {
                let secondsRemaining = Double(mahToNextCycle) / mahPerSecond
                let formatted = formatDuration(secondsRemaining)
                lastTimeToNextCycleValue = formatted
                timeToNextCycleText = appendReachTime(
                    to: "Time Until Next Cycle: \(formatted)",
                    seconds: secondsRemaining
                )
                return
            }
        }

        if let lastTimeToNextCycleValue {
            timeToNextCycleText = "Time Until Next Cycle: \(lastTimeToNextCycleValue) (Unpaused - Calculating)"
        } else {
            timeToNextCycleText = "Time Until Next Cycle: —"
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "—"
    }

    private func appendReachTime(to base: String, seconds: Double) -> String {
        guard seconds > 0 else { return base }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let target = Date().addingTimeInterval(seconds)
        return "\(base) (\(formatter.string(from: target)))"
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
            defaults.set(0.0, forKey: DefaultsKeys.todayMahUsed)
            totalMahUsedToday = 0
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
        let cachedMahUsed = defaults.double(forKey: DefaultsKeys.todayMahUsed)
        if cachedMahUsed == 0, let existing, existing.totalMahUsed > 0 {
            defaults.set(existing.totalMahUsed, forKey: DefaultsKeys.todayMahUsed)
        }
        let totalMahUsed = updateMahUsed(existing: existing)
        totalMahUsedToday = totalMahUsed
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
        try? modelContext.save()
    }

    func incrementTodayCycle(modelContext: ModelContext) {
        let todayDate = Calendar.current.startOfDay(for: Date())
        let existing = fetchDailyCycle(for: todayDate, modelContext: modelContext)
        let currentCycles = existing?.cycles ?? cyclesToday ?? 0
        let newCycles = currentCycles + 1

        upsertDailyCycle(
            for: todayDate,
            modelContext: modelContext,
            existing: existing
        ) { daily in
            daily.cycles = newCycles
        }

        if let cycleCount {
            let adjustedBaseline = max(0, cycleCount - newCycles)
            UserDefaults.standard.set(adjustedBaseline, forKey: DefaultsKeys.cyclesBaselineCount)
            UserDefaults.standard.set(Self.dayFormatter.string(from: Date()), forKey: DefaultsKeys.cyclesBaselineDate)
        }

        cyclesToday = newCycles
        try? modelContext.save()
    }

    private func updateMahUsed(existing: DailyCycle?) -> Double {
        guard let currentCapacityMah else {
            return UserDefaults.standard.double(forKey: DefaultsKeys.todayMahUsed)
        }

        let defaults = UserDefaults.standard
        let lastCapacity = defaults.object(forKey: DefaultsKeys.lastCapacityMahForUsage) as? Int
        let previousTotal = defaults.double(forKey: DefaultsKeys.todayMahUsed)

        defer {
            defaults.set(currentCapacityMah, forKey: DefaultsKeys.lastCapacityMahForUsage)
        }

        guard let lastCapacity, currentCapacityMah < lastCapacity else {
            return previousTotal
        }

        let delta = Double(lastCapacity - currentCapacityMah)
        let updatedTotal = previousTotal + max(0, delta)
        defaults.set(updatedTotal, forKey: DefaultsKeys.todayMahUsed)
        return updatedTotal
    }

    private func calculateRawCycles(totalMahUsed: Double) -> Double {
        guard let designCapacityMah, designCapacityMah > 0 else {
            return 0
        }

        return totalMahUsed / Double(designCapacityMah)
    }

    func revealStoreLocation(modelContext: ModelContext) {
        let configuredURL = modelContext.container.configurations.first?.url
        let url = (configuredURL?.path == "/dev/null") ? persistentStoreURLFallback() : configuredURL
        guard let url else {
            storeLocationMessage = "No on-disk store URL available."
            return
        }

        let path = url.path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        storeLocationMessage = "Path copied to clipboard:\n\(path)"
    }

    private func persistentStoreURLFallback() -> URL? {
        guard let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directory = supportDirectory.appendingPathComponent("BatteryTracker", isDirectory: true)
        return directory.appendingPathComponent("BatteryTracker.store")
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
