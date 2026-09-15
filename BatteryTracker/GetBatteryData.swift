//
//  GetBatteryData.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/17/26.
//

import Foundation
import IOKit
import IOKit.ps

// MARK: - Battery registry snapshot

/// A single read of the AppleSmartBattery IOKit registry entry.
///
/// All values are captured with one service lookup instead of opening the
/// service once per property, which matters because the app polls every 1–5 s.
///
/// On macOS 27 the mAh values live in the "BatteryData" sub-dictionary
/// (RemainingCapacity/FullChargeCapacity/DesignCapacity); the top-level
/// CurrentCapacity/MaxCapacity keys only report percentages. Older systems
/// expose top-level AppleRawCurrentCapacity/AppleRawMaxCapacity/DesignCapacity
/// instead, so both locations are checked.
struct BatterySnapshot {
    let cycleCount: Int?
    let currentCapacityMah: Int?
    let maxCapacityMah: Int?
    let designCapacityMah: Int?
    let healthText: String?

    static func capture() -> BatterySnapshot {
        let properties = batteryRegistryProperties() ?? [:]
        let batteryData = properties["BatteryData"] as? [String: Any] ?? [:]

        let capacity = capacityMah(from: properties, batteryData: batteryData)
        let design = intValue(batteryData["DesignCapacity"]) ?? intValue(properties["DesignCapacity"])
        return BatterySnapshot(
            cycleCount: intValue(properties["CycleCount"]),
            currentCapacityMah: capacity?.current,
            maxCapacityMah: capacity?.max,
            designCapacityMah: design,
            healthText: healthText(from: properties, maxCapacityMah: capacity?.max, designCapacityMah: design)
        )
    }

    private static func capacityMah(
        from properties: [String: Any],
        batteryData: [String: Any]
    ) -> (current: Int, max: Int)? {
        // macOS 27: real mAh values are in BatteryData.
        if let remaining = intValue(batteryData["RemainingCapacity"]),
           let fullCharge = intValue(batteryData["FullChargeCapacity"]),
           fullCharge > 0 {
            return (remaining, fullCharge)
        }

        // Older systems: top-level raw capacity keys.
        if let rawCurrent = intValue(properties["AppleRawCurrentCapacity"]),
           let rawMax = intValue(properties["AppleRawMaxCapacity"]) {
            return (rawCurrent, rawMax)
        }

        // CurrentCapacity/MaxCapacity report percentages (0-100) on Apple
        // silicon, so only trust them when they look like real mAh values.
        if let current = intValue(properties["CurrentCapacity"]),
           let max = intValue(properties["MaxCapacity"]),
           current > 200,
           max > 200 {
            return (current, max)
        }

        if let current = intValue(properties["DesignCapacity"]),
           let max = intValue(properties["MaxCapacity"]),
           current > 200,
           max > 200 {
            return (current, max)
        }

        return nil
    }

    private static func healthText(
        from properties: [String: Any],
        maxCapacityMah: Int?,
        designCapacityMah: Int?
    ) -> String? {
        if let health = stringValue(properties["BatteryHealth"]) {
            return health
        }

        if let condition = stringValue(properties["BatteryHealthCondition"]) {
            return condition
        }

        if let maxCapacityMah,
           let designCapacityMah,
           maxCapacityMah > 0,
           designCapacityMah > 0 {
            let percent = Int((Double(maxCapacityMah) / Double(designCapacityMah) * 100.0).rounded())
            return "\(percent)%"
        }

        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func batteryRegistryProperties() -> [String: Any]? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else {
        return nil
    }
    defer {
        IOObjectRelease(service)
    }

    var unmanagedProperties: Unmanaged<CFMutableDictionary>?
    let result = IORegistryEntryCreateCFProperties(service, &unmanagedProperties, kCFAllocatorDefault, 0)
    guard result == KERN_SUCCESS else {
        return nil
    }

    return unmanagedProperties?.takeRetainedValue() as? [String: Any]
}

private func intValue(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue ?? (value as? Int)
}

private func doubleValue(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue ?? (value as? Double)
}

// MARK: - Power source snapshot

enum PowerSourceState: String {
    case ac
    case battery
    case unknown
}

struct BatteryTimeRemaining {
    let minutes: Int
    let isCharging: Bool
}

/// A single read of the IOPS power source list.
///
/// Captures state, time remaining, and health condition in one pass instead of
/// walking the power source list three separate times per refresh.
struct PowerSourceSnapshot {
    let state: PowerSourceState
    let timeRemaining: BatteryTimeRemaining?
    let officialHealthText: String?

    static func capture() -> PowerSourceSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSourceSnapshot(state: .unknown, timeRemaining: nil, officialHealthText: nil)
        }
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

        var state: PowerSourceState = .unknown
        var timeRemaining: BatteryTimeRemaining?
        var officialHealthText: String?

        for powerSource in list {
            guard let description = IOPSGetPowerSourceDescription(info, powerSource)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if state == .unknown, let sourceState = description[kIOPSPowerSourceStateKey] as? String {
                if sourceState == kIOPSACPowerValue {
                    state = .ac
                } else if sourceState == kIOPSBatteryPowerValue {
                    state = .battery
                }
            }

            if timeRemaining == nil {
                let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
                let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int
                let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int

                if isCharging, let timeToFull, timeToFull >= 0 {
                    timeRemaining = BatteryTimeRemaining(minutes: timeToFull, isCharging: true)
                } else if let timeToEmpty, timeToEmpty >= 0 {
                    timeRemaining = BatteryTimeRemaining(minutes: timeToEmpty, isCharging: false)
                }
            }

            if officialHealthText == nil {
                officialHealthText = healthText(from: description)
            }
        }

        return PowerSourceSnapshot(state: state, timeRemaining: timeRemaining, officialHealthText: officialHealthText)
    }

    private static func healthText(from description: [String: Any]) -> String? {
        if let condition = description["BatteryHealthCondition"] as? String {
            let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let health = description["BatteryHealth"] as? String {
            let trimmed = health.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "Good" {
                return "Normal"
            }
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }
}

// MARK: - Official battery health percent

private let officialHealthPercentCacheInterval: TimeInterval = 60 * 10
private var cachedOfficialHealthPercent: Int?
private var lastOfficialHealthPercentFetch: Date?

/// Returns the "Maximum Capacity" percentage that System Settings reports.
///
/// The system_profiler invocation is slow, so the result is cached for ten
/// minutes and the process runs off the main actor to keep the UI responsive.
func getOfficialBatteryHealthPercent() async -> Int? {
    if let cached = cachedOfficialHealthPercent,
       let lastFetch = lastOfficialHealthPercentFetch,
       Date().timeIntervalSince(lastFetch) < officialHealthPercentCacheInterval {
        return cached
    }

    let profilerPercent = await Task.detached(priority: .utility) {
        fetchOfficialBatteryHealthPercentFromSystemProfiler()
    }.value
    let percent = profilerPercent ?? officialBatteryHealthPercentFromRegistry()

    if profilerPercent != nil {
        cachedOfficialHealthPercent = percent
        lastOfficialHealthPercentFetch = Date()
    } else {
        cachedOfficialHealthPercent = nil
        lastOfficialHealthPercentFetch = nil
    }

    return percent
}

private func officialBatteryHealthPercentFromRegistry() -> Int? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else {
        return nil
    }
    defer {
        IOObjectRelease(service)
    }

    var unmanagedProperties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &unmanagedProperties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any] else {
        return nil
    }

    guard let designCapacity = (properties["DesignCapacity"] as? NSNumber)?.doubleValue,
          designCapacity > 0 else {
        return nil
    }

    let maxCapacity = (properties["NominalChargeCapacity"] as? NSNumber)?.doubleValue
        ?? (properties["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
        ?? (properties["MaxCapacity"] as? NSNumber)?.doubleValue

    guard let maxCapacity, maxCapacity > 0 else {
        return nil
    }

    return Int((maxCapacity / designCapacity * 100.0).rounded())
}

private nonisolated func fetchOfficialBatteryHealthPercentFromSystemProfiler() -> Int? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["-detailLevel", "mini", "SPPowerDataType"]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    do {
        try process.run()
    } catch {
        return nil
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let output = String(data: data, encoding: .utf8) else {
        return nil
    }

    for line in output.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("Maximum Capacity:") else {
            continue
        }

        let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        if digits.isEmpty == false {
            return Int(String(String.UnicodeScalarView(digits)))
        }
    }

    return nil
}
