//
//  CSVBackupService.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/24/26.
//

import Foundation
import SwiftData

struct CSVBackupService {
    struct ImportResult {
        let insertedDaily: Int
        let insertedBreakdown: Int
        let skippedDaily: Int
        let skippedBreakdown: Int
    }

    static func exportBackup(
        dailyCycles: [DailyCycle],
        to directoryURL: URL
    ) throws {
        let sortedDaily = dailyCycles.sorted { $0.date < $1.date }
        var dailyPKById: [PersistentIdentifier: Int] = [:]
        for (index, daily) in sortedDaily.enumerated() {
            dailyPKById[daily.id] = index + 1
        }

        let dailyHeader = "Z_PK,Z_ENT,Z_OPT,ZCYCLES,ZDATE,ZRAWCYCLES,ZTIMEONBATTERY,ZTIMEPLUGGEDIN,ZTOTALMAHUSED"
        var dailyLines = [dailyHeader]
        for daily in sortedDaily {
            let pk = dailyPKById[daily.id] ?? 0
            let dateValue = daily.date.timeIntervalSinceReferenceDate
            let line = [
                String(pk),
                "2",
                "1",
                String(daily.cycles),
                String(format: "%.0f", dateValue),
                String(format: "%.12f", daily.rawCycles),
                String(format: "%.6f", daily.timeOnBattery),
                String(format: "%.6f", daily.timePluggedIn),
                String(format: "%.6f", daily.totalMahUsed)
            ].joined(separator: ",")
            dailyLines.append(line)
        }

        let breakdownHeader = "Z_PK,Z_ENT,Z_OPT,ZINDEX,ZISPARTIAL,Z2CYCLEBREAKDOWNS,ZCOMPLETIONPERCENT,ZMAHUSED,ZID"
        var breakdownLines = [breakdownHeader]
        var breakdownPK = 1
        for daily in sortedDaily {
            let dailyPK = dailyPKById[daily.id] ?? 0
            let sortedBreakdowns = daily.cycleBreakdowns.sorted { $0.index < $1.index }
            for breakdown in sortedBreakdowns {
                let line = [
                    String(breakdownPK),
                    "16002",
                    "1",
                    String(breakdown.index),
                    breakdown.isPartial ? "1" : "0",
                    String(dailyPK),
                    String(format: "%.6f", breakdown.completionPercent),
                    String(format: "%.6f", breakdown.mahUsed),
                    ""
                ].joined(separator: ",")
                breakdownLines.append(line)
                breakdownPK += 1
            }
        }

        let dailyURL = directoryURL.appendingPathComponent("ZDAILYCYCLE.csv")
        let breakdownURL = directoryURL.appendingPathComponent("ZCYCLEBREAKDOWN.csv")
        try dailyLines.joined(separator: "\n").write(to: dailyURL, atomically: true, encoding: .utf8)
        try breakdownLines.joined(separator: "\n").write(to: breakdownURL, atomically: true, encoding: .utf8)
    }

    static func restoreBackup(urls: [URL], modelContext: ModelContext) throws -> ImportResult {
        var dailyCSV: (header: [String], rows: [[String]])?
        var breakdownCSV: (header: [String], rows: [[String]])?
        var insertedDailyCount = 0
        var insertedBreakdownCount = 0
        var skippedDailyCount = 0
        var skippedBreakdownCount = 0

        for url in urls {
            let parsed = try parseCSV(url: url)
            let lowercasedName = url.lastPathComponent.lowercased()
            if lowercasedName.contains("zdailycycle") {
                dailyCSV = parsed
            } else if lowercasedName.contains("zcyclebreakdown") {
                breakdownCSV = parsed
            }
        }

        guard let dailyCSV else {
            throw CSVBackupError.missingDailyCycles
        }

        let existing = (try? modelContext.fetch(FetchDescriptor<DailyCycle>())) ?? []
        for entry in existing {
            modelContext.delete(entry)
        }

        let calendar = Calendar.current
        var dailyByPK: [Int: DailyCycle] = [:]
        let dailyHeader = headerIndexMap(dailyCSV.header)
        try ensureRequiredColumns(["Z_PK", "ZDATE"], header: dailyHeader, fileName: "ZDAILYCYCLE.csv")
        for row in dailyCSV.rows {
            guard let pk = intValue(row, key: "Z_PK", header: dailyHeader),
                  let dateValue = doubleValue(row, key: "ZDATE", header: dailyHeader) else {
                skippedDailyCount += 1
                continue
            }

            let date = Date(timeIntervalSinceReferenceDate: dateValue)
            let startDate = calendar.startOfDay(for: date)
            let cycles = intValue(row, key: "ZCYCLES", header: dailyHeader) ?? 0
            let rawCycles = doubleValue(row, key: "ZRAWCYCLES", header: dailyHeader) ?? 0
            let timeOnBattery = doubleValue(row, key: "ZTIMEONBATTERY", header: dailyHeader) ?? 0
            let timePluggedIn = doubleValue(row, key: "ZTIMEPLUGGEDIN", header: dailyHeader) ?? 0
            let totalMahUsed = doubleValue(row, key: "ZTOTALMAHUSED", header: dailyHeader) ?? 0

            let daily = DailyCycle(
                date: startDate,
                cycles: cycles,
                rawCycles: rawCycles,
                totalMahUsed: totalMahUsed,
                timeOnBattery: timeOnBattery,
                timePluggedIn: timePluggedIn
            )
            modelContext.insert(daily)
            dailyByPK[pk] = daily
            insertedDailyCount += 1
        }

        if let breakdownCSV {
            let breakdownHeader = headerIndexMap(breakdownCSV.header)
            try ensureRequiredColumns(
                ["ZMAHUSED", "ZCOMPLETIONPERCENT"],
                header: breakdownHeader,
                fileName: "ZCYCLEBREAKDOWN.csv"
            )
            guard let breakdownKeyColumn = breakdownKeyColumnName(from: breakdownHeader) else {
                throw CSVBackupError.missingColumns(fileName: "ZCYCLEBREAKDOWN.csv", columns: ["Z2CYCLEBREAKDOWNS (or other DailyCycle FK)"])
            }
            var unlinkedBreakdowns: [(index: Int?, isPartial: Bool, completionPercent: Double, mahUsed: Double)] = []
            for row in breakdownCSV.rows {
                let index = intValue(row, key: "ZINDEX", header: breakdownHeader)
                let isPartial = (intValue(row, key: "ZISPARTIAL", header: breakdownHeader) ?? 0) != 0
                let completionPercent = doubleValue(row, key: "ZCOMPLETIONPERCENT", header: breakdownHeader) ?? 0
                let mahUsed = doubleValue(row, key: "ZMAHUSED", header: breakdownHeader) ?? 0

                if let dailyKey = intValue(row, key: breakdownKeyColumn, header: breakdownHeader),
                   let daily = dailyByPK[dailyKey] {
                    let resolvedIndex = index ?? (daily.cycleBreakdowns.map(\.index).max() ?? 0) + 1
                    let breakdown = CycleBreakdown(
                        index: resolvedIndex,
                        mahUsed: mahUsed,
                        isPartial: isPartial,
                        completionPercent: completionPercent
                    )
                    daily.cycleBreakdowns.append(breakdown)
                    insertedBreakdownCount += 1
                } else {
                    unlinkedBreakdowns.append((index: index, isPartial: isPartial, completionPercent: completionPercent, mahUsed: mahUsed))
                }
            }

            if unlinkedBreakdowns.isEmpty == false {
                insertedBreakdownCount += allocateUnlinkedBreakdowns(unlinkedBreakdowns, to: dailyByPK)
            }

            skippedBreakdownCount = max(0, breakdownCSV.rows.count - insertedBreakdownCount)
        }

        try modelContext.save()

        return ImportResult(
            insertedDaily: insertedDailyCount,
            insertedBreakdown: insertedBreakdownCount,
            skippedDaily: skippedDailyCount,
            skippedBreakdown: skippedBreakdownCount
        )
    }

    private static func parseCSV(url: URL) throws -> (header: [String], rows: [[String]]) {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerLine = lines.first else {
            throw CSVBackupError.emptyFile
        }

        let header = headerLine
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var rows: [[String]] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                continue
            }
            let values = trimmed
                .split(separator: ",", omittingEmptySubsequences: false)
                .map(String.init)
            rows.append(values)
        }
        return (header, rows)
    }

    private static func headerIndexMap(_ header: [String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })
    }

    private static func ensureRequiredColumns(_ required: [String], header: [String: Int], fileName: String) throws {
        let missing = required.filter { header[$0] == nil }
        if missing.isEmpty == false {
            throw CSVBackupError.missingColumns(fileName: fileName, columns: missing)
        }
    }

    private static func breakdownKeyColumnName(from header: [String: Int]) -> String? {
        let candidates = [
            "Z2CYCLEBREAKDOWNS",
            "ZDAILYCYCLE",
            "Z1DAILYCYCLE",
            "ZDAILYCYCLEID",
            "ZDAILYCYCLES",
            "Z2DAILYCYCLES"
        ]
        return candidates.first { header[$0] != nil }
    }

    private static func stringValue(_ row: [String], key: String, header: [String: Int]) -> String? {
        guard let index = header[key], index < row.count else {
            return nil
        }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func intValue(_ row: [String], key: String, header: [String: Int]) -> Int? {
        guard let value = stringValue(row, key: key, header: header) else {
            return nil
        }
        return Int(value)
    }

    private static func doubleValue(_ row: [String], key: String, header: [String: Int]) -> Double? {
        guard let value = stringValue(row, key: key, header: header) else {
            return nil
        }
        return Double(value)
    }

    private static func allocateUnlinkedBreakdowns(
        _ breakdowns: [(index: Int?, isPartial: Bool, completionPercent: Double, mahUsed: Double)],
        to dailyByPK: [Int: DailyCycle]
    ) -> Int {
        guard breakdowns.isEmpty == false else {
            return 0
        }

        let orderedDaily = dailyByPK.values.sorted { $0.date < $1.date }
        guard orderedDaily.isEmpty == false else {
            return 0
        }

        let totalCycles = orderedDaily.reduce(0) { $0 + max(0, $1.cycles) }
        var assigned = 0
        var cursor = 0

        if totalCycles > 0 {
            for daily in orderedDaily {
                let target = max(0, daily.cycles)
                guard target > 0 else { continue }
                for _ in 0..<target where cursor < breakdowns.count {
                    let row = breakdowns[cursor]
                    let resolvedIndex = row.index ?? (daily.cycleBreakdowns.map(\.index).max() ?? 0) + 1
                    daily.cycleBreakdowns.append(
                        CycleBreakdown(
                            index: resolvedIndex,
                            mahUsed: row.mahUsed,
                            isPartial: row.isPartial,
                            completionPercent: row.completionPercent
                        )
                    )
                    cursor += 1
                    assigned += 1
                }
            }
        } else {
            let perDay = breakdowns.count / orderedDaily.count
            let remainder = breakdowns.count % orderedDaily.count
            for (index, daily) in orderedDaily.enumerated() {
                let target = perDay + (index < remainder ? 1 : 0)
                for _ in 0..<target where cursor < breakdowns.count {
                    let row = breakdowns[cursor]
                    let resolvedIndex = row.index ?? (daily.cycleBreakdowns.map(\.index).max() ?? 0) + 1
                    daily.cycleBreakdowns.append(
                        CycleBreakdown(
                            index: resolvedIndex,
                            mahUsed: row.mahUsed,
                            isPartial: row.isPartial,
                            completionPercent: row.completionPercent
                        )
                    )
                    cursor += 1
                    assigned += 1
                }
            }
        }

        if cursor < breakdowns.count, let last = orderedDaily.last {
            while cursor < breakdowns.count {
                let row = breakdowns[cursor]
                let resolvedIndex = row.index ?? (last.cycleBreakdowns.map(\.index).max() ?? 0) + 1
                last.cycleBreakdowns.append(
                    CycleBreakdown(
                        index: resolvedIndex,
                        mahUsed: row.mahUsed,
                        isPartial: row.isPartial,
                        completionPercent: row.completionPercent
                    )
                )
                cursor += 1
                assigned += 1
            }
        }

        return assigned
    }
}

enum CSVBackupError: LocalizedError {
    case emptyFile
    case missingDailyCycles
    case missingColumns(fileName: String, columns: [String])

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "CSV file is empty."
        case .missingDailyCycles:
            return "Missing ZDAILYCYCLE.csv in the selected files."
        case .missingColumns(let fileName, let columns):
            let list = columns.joined(separator: ", ")
            return "Missing columns in \(fileName): \(list)."
        }
    }
}
