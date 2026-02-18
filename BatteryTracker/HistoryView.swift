//
//  HistoryView.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/17/26.
//

import Combine
import Foundation
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \DailyCycle.date, order: .reverse) private var entries: [DailyCycle]
    @State private var selection: DailyCycle?
    @State private var updater = BatteryStatusViewModel()
    @Environment(\.modelContext) private var modelContext

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Summary") {
                    SummaryRow(label: "Total Cycles Gained", value: "\(totalCycles)")
                    SummaryRow(label: "Total Raw Cycles", value: formatDecimal(totalRawCycles))
                    SummaryRow(label: "Total mAh Used", value: formatDecimal(totalMahUsed))
                    SummaryRow(label: "Total Time on Battery", value: formatDuration(totalTimeOnBattery))
                    SummaryRow(label: "Total Time Plugged In", value: formatDuration(totalTimePluggedIn))
                }

                Section("Days") {
                    ForEach(entries) { entry in
                        Text(formatDate(entry.date))
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
            if selection == nil {
                selection = entries.first
            }
        }
        .onDisappear {
            AppDelegate.shared?.setDockVisible(false)
        }
        .onChange(of: entries) { _, newEntries in
            if selection == nil {
                selection = newEntries.first
            }
        }
        .onReceive(timer) { _ in
            updater.updateBatteryInfo(modelContext: modelContext)
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

    private func formatDate(_ date: Date) -> String {
        let output = DateFormatter()
        output.calendar = Calendar.current
        output.locale = Locale(identifier: "en_US_POSIX")
        output.dateFormat = "MMMM d, yyyy"
        return output.string(from: date)
    }

    private func formatDecimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "—"
    }
}

private struct DailyStatsDetailView: View {
    let entry: DailyCycle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatDate(entry.date))
                .font(.title2)
                .bold()

            StatRow(label: "Cycles Gained", value: "\(entry.cycles)")
            StatRow(label: "Raw Cycles (mAh)", value: formatDecimal(entry.rawCycles))
            StatRow(label: "Total mAh Used", value: formatDecimal(entry.totalMahUsed))
            StatRow(label: "Time on Battery", value: formatDuration(entry.timeOnBattery))
            StatRow(label: "Time Plugged In", value: formatDuration(entry.timePluggedIn))

            Spacer()
        }
        .padding()
    }

    private func formatDate(_ date: Date) -> String {
        let output = DateFormatter()
        output.calendar = Calendar.current
        output.locale = Locale(identifier: "en_US_POSIX")
        output.dateFormat = "MMMM d, yyyy"
        return output.string(from: date)
    }

    private func formatDecimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "—"
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

private struct SummaryRow: View {
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
}
