//
//  HistoryView.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/17/26.
//

import Foundation
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \DailyCycle.date, order: .reverse) private var entries: [DailyCycle]
    @State private var selection: DailyCycle?
    @State private var updater = BatteryStatusViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Summary") {
                    StatRow(label: "Total Cycles Gained", value: "\(totalCycles)")
                    StatRow(label: "Total Raw Cycles", value: Formatting.decimal(totalRawCycles))
                    StatRow(label: "Total mAh Used", value: Formatting.decimal(totalMahUsed))
                    StatRow(label: "Total Time on Battery", value: Formatting.duration(totalTimeOnBattery))
                    StatRow(label: "Total Time Plugged In", value: Formatting.duration(totalTimePluggedIn))
                }

                Section("Days") {
                    ForEach(entries) { entry in
                        Text(Formatting.date(entry.date))
                            .tag(entry)
                    }
                }
            }
            .navigationTitle("Daily Stats")
        } detail: {
            if let selection {
                DailyStatsDetailView(entry: selection)
            } else {
                Text("Select a day")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .onAppear {
            AppDelegate.shared?.setDockVisible(true)
            UserDefaults.standard.set(true, forKey: SharedDefaultsKeys.historyVisible)
            if selection == nil {
                selection = entries.first
            }
        }
        .onDisappear {
            AppDelegate.shared?.setDockVisible(false)
            UserDefaults.standard.set(false, forKey: SharedDefaultsKeys.historyVisible)
        }
        .onChange(of: entries) { _, newEntries in
            if selection == nil {
                selection = newEntries.first
            }
        }
        .task {
            while !Task.isCancelled {
                updater.updateBatteryInfo(modelContext: modelContext)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var totalCycles: Int {
        entries.reduce(0) { $0 + $1.cycles }
    }

    private var totalRawCycles: Double {
        entries.reduce(0) { $0 + $1.rawCycles }
    }

    private var totalMahUsed: Double {
        entries.reduce(0) { $0 + $1.totalMahUsed }
    }

    private var totalTimeOnBattery: Double {
        entries.reduce(0) { $0 + $1.timeOnBattery }
    }

    private var totalTimePluggedIn: Double {
        entries.reduce(0) { $0 + $1.timePluggedIn }
    }
}

private struct DailyStatsDetailView: View {
    let entry: DailyCycle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Formatting.date(entry.date))
                .font(.title2)
                .bold()

            StatRow(label: "Cycles Gained", value: "\(entry.cycles)")
            StatRow(label: "Raw Cycles (mAh)", value: Formatting.decimal(entry.rawCycles))
            StatRow(label: "Total mAh Used", value: Formatting.decimal(entry.totalMahUsed))
            StatRow(label: "Time on Battery", value: Formatting.duration(entry.timeOnBattery))
            StatRow(label: "Time Plugged In", value: Formatting.duration(entry.timePluggedIn))

            DisclosureGroup("Cycle Breakdown") {
                if entry.cycleBreakdowns.isEmpty {
                    Text("No cycle breakdown yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedBreakdowns) { breakdown in
                        HStack {
                            Text(label(for: breakdown))
                            Spacer()
                            Text("\(Formatting.decimal(breakdown.mahUsed)) mAh")
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    private var sortedBreakdowns: [CycleBreakdown] {
        entry.cycleBreakdowns.sorted { $0.index < $1.index }
    }

    private func label(for breakdown: CycleBreakdown) -> String {
        if breakdown.isPartial {
            return "Cycle \(breakdown.index) (Partial - \(Formatting.percent(breakdown.completionPercent)))"
        }
        return "Cycle \(breakdown.index)"
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: DailyCycle.self, inMemory: true)
}
