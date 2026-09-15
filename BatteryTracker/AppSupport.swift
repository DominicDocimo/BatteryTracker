//
//  AppSupport.swift
//  BatteryTracker
//
//  Shared constants and cached formatters used across the app.
//

import Foundation

/// The cycle-count goal the app tracks progress toward.
enum BatteryGoal {
    static let targetCycles = 1000

    static var deadline: Date? {
        Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1))
    }

    static func daysUntilDeadline(from date: Date = Date()) -> Int? {
        guard let deadline else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: date, to: deadline).day
    }
}

enum SharedDefaultsKeys {
    static let historyVisible = "historyVisible"
}

/// Cached formatters — creating Formatter instances is expensive, so they are
/// built once and reused by every view and view model.
enum Formatting {
    private static let hoursMinutesFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let paddedDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.2f%%", value)
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }

    /// Hours and minutes, e.g. "3h 24m".
    static func hoursMinutes(_ seconds: Double) -> String {
        hoursMinutesFormatter.string(from: seconds) ?? "—"
    }

    /// Hours, minutes, and seconds with zero padding, e.g. "3h 24m 05s".
    static func duration(_ seconds: Double) -> String {
        paddedDurationFormatter.string(from: seconds) ?? "—"
    }
}
