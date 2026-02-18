//
//  GetBatteryData.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/17/26.
//

import Foundation
import IOKit
import IOKit.ps

private let appleSmartBatteryService = "AppleSmartBattery"
private let cycleCountRegistryKey = "CycleCount"
private let currentCapacityRegistryKey = "CurrentCapacity"
private let maxCapacityRegistryKey = "MaxCapacity"
private let rawCurrentCapacityRegistryKey = "AppleRawCurrentCapacity"
private let rawMaxCapacityRegistryKey = "AppleRawMaxCapacity"
private let designCapacityRegistryKey = "DesignCapacity"
private let nominalChargeCapacityRegistryKey = "NominalChargeCapacity"
private let batteryHealthRegistryKey = "BatteryHealth"
private let batteryHealthConditionRegistryKey = "BatteryHealthCondition"
private let officialHealthPercentCacheInterval: TimeInterval = 60 * 10
private var cachedOfficialHealthPercent: Int?
private var lastOfficialHealthPercentFetch: Date?

private func getBatteryRegistryValue(_ key: String) -> Any? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(appleSmartBatteryService))
    guard service != 0 else {
        return nil
    }
    defer {
        IOObjectRelease(service)
    }

    return IORegistryEntryCreateCFProperty(service,
                                          key as CFString,
                                          kCFAllocatorDefault,
                                          0)?.takeRetainedValue()
}

private func getBatteryRegistryInt(_ key: String) -> Int? {
    guard let value = getBatteryRegistryValue(key) else {
        return nil
    }

    if let number = value as? NSNumber {
        return number.intValue
    }

    return value as? Int
}

private func getBatteryRegistryDouble(_ key: String) -> Double? {
    guard let value = getBatteryRegistryValue(key) else {
        return nil
    }

    if let number = value as? NSNumber {
        return number.doubleValue
    }

    return value as? Double
}
private func getBatteryRegistryString(_ key: String) -> String? {
    guard let value = getBatteryRegistryValue(key) else {
        return nil
    }

    if let string = value as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    return nil
}

func getBatteryCycleCount() -> Int? {
    return getBatteryRegistryInt(cycleCountRegistryKey)
}

func getBatteryHealthText() -> String? {
    if let health = getBatteryRegistryString(batteryHealthRegistryKey), !health.isEmpty {
        return health
    }

    if let condition = getBatteryRegistryString(batteryHealthConditionRegistryKey), !condition.isEmpty {
        return condition
    }

    if let maxCapacity = getBatteryRegistryDouble(rawMaxCapacityRegistryKey) ?? getBatteryRegistryDouble(maxCapacityRegistryKey),
       let designCapacity = getBatteryRegistryDouble(designCapacityRegistryKey),
       maxCapacity > 0,
       designCapacity > 0 {
        let percent = Int((maxCapacity / designCapacity * 100.0).rounded())
        return "\(percent)%"
    }

    return nil
}

enum PowerSourceState: String {
    case ac
    case battery
    case unknown
}

func getPowerSourceState() -> PowerSourceState {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
        return .unknown
    }
    let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

    for powerSource in list {
        guard let description = IOPSGetPowerSourceDescription(info, powerSource)?
            .takeUnretainedValue() as? [String: Any] else {
            continue
        }

        if let state = description[kIOPSPowerSourceStateKey] as? String {
            if state == kIOPSACPowerValue {
                return .ac
            }
            if state == kIOPSBatteryPowerValue {
                return .battery
            }
        }
    }

    return .unknown
}

struct BatteryTimeRemaining {
    let minutes: Int
    let isCharging: Bool
}

func getBatteryTimeRemaining() -> BatteryTimeRemaining? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
        return nil
    }
    let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

    for powerSource in list {
        guard let description = IOPSGetPowerSourceDescription(info, powerSource)?
            .takeUnretainedValue() as? [String: Any] else {
            continue
        }

        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int
        let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int

        if isCharging, let timeToFull, timeToFull >= 0 {
            return BatteryTimeRemaining(minutes: timeToFull, isCharging: true)
        }

        if let timeToEmpty, timeToEmpty >= 0 {
            return BatteryTimeRemaining(minutes: timeToEmpty, isCharging: false)
        }
    }

    return nil
}

func getOfficialBatteryHealthText() -> String? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
        return nil
    }
    let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

    for powerSource in list {
        guard let description = IOPSGetPowerSourceDescription(info, powerSource)?
            .takeUnretainedValue() as? [String: Any] else {
            continue
        }

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
    }

    return nil
}

func getOfficialBatteryHealthPercent() async -> Int? {
    if let cached = cachedOfficialHealthPercent,
       let lastFetch = lastOfficialHealthPercentFetch,
       Date().timeIntervalSince(lastFetch) < officialHealthPercentCacheInterval {
        return cached
    }

    let profilerPercent = fetchOfficialBatteryHealthPercentFromSystemProfiler()
    let registryPercent = getOfficialBatteryHealthPercentFromRegistry()
    let percent = profilerPercent ?? registryPercent

    if profilerPercent != nil {
        cachedOfficialHealthPercent = percent
        lastOfficialHealthPercentFetch = Date()
    } else {
        cachedOfficialHealthPercent = nil
        lastOfficialHealthPercentFetch = nil
    }

    return percent
}

private func getOfficialBatteryHealthPercentFromRegistry() -> Int? {
    guard let designCapacity = getBatteryRegistryDouble(designCapacityRegistryKey),
          designCapacity > 0 else {
        return nil
    }

    let maxCapacity = getBatteryRegistryDouble(nominalChargeCapacityRegistryKey)
        ?? getBatteryRegistryDouble(rawMaxCapacityRegistryKey)
        ?? getBatteryRegistryDouble(maxCapacityRegistryKey)

    guard let maxCapacity, maxCapacity > 0 else {
        return nil
    }

    return Int((maxCapacity / designCapacity * 100.0).rounded())
}

private func fetchOfficialBatteryHealthPercentFromSystemProfiler() -> Int? {
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

    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        return nil
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
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

func getBatteryCapacityMah() -> (current: Int, max: Int)? {
    if let rawCurrent = getBatteryRegistryInt(rawCurrentCapacityRegistryKey),
       let rawMax = getBatteryRegistryInt(rawMaxCapacityRegistryKey) {
        return (rawCurrent, rawMax)
    }

    if let current = getBatteryRegistryInt(currentCapacityRegistryKey),
       let max = getBatteryRegistryInt(maxCapacityRegistryKey),
       current > 200,
       max > 200 {
        return (current, max)
    }

    if let current = getBatteryRegistryInt(designCapacityRegistryKey),
       let max = getBatteryRegistryInt(maxCapacityRegistryKey),
       current > 200,
       max > 200 {
        return (current, max)
    }
    return nil
}

func getBatteryDesignCapacityMah() -> Int? {
    return getBatteryRegistryInt(designCapacityRegistryKey)
}
