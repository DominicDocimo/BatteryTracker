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
    @State private var isEditingSelection = false
    @AppStorage("isDevModeEnabled") private var isDevModeEnabled = false
    @AppStorage("isEditModeEnabled") private var isEditModeEnabled = false
    @AppStorage("isTestEditsEnabled") private var isTestEditsEnabled = false
    @State private var testOverrides: [PersistentIdentifier: DailyCycleOverride] = [:]
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

                if isDevModeEnabled {
                    Section("Dev Mode") {
                        Toggle("Edit Mode", isOn: $isEditModeEnabled)
                        Toggle("Test Edits", isOn: $isTestEditsEnabled)
                    }
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
            ScrollView {
                if let selection {
                    VStack(alignment: .leading, spacing: 8) {
                        if isEditModeEnabled {
                            Button(isEditingSelection ? "Done Editing" : "Edit") {
                                isEditingSelection.toggle()
                            }
                        }
                        DailyStatsDetailView(
                            entry: selection,
                            isEditing: isEditingSelection,
                            isTestEditsEnabled: isTestEditsEnabled,
                            override: testOverrides[selection.id]
                        ) { override in
                            testOverrides[selection.id] = override
                        }
                    }
                } else {
                    Text("Select a day")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .onAppear {
            AppDelegate.shared?.setDockVisible(true)
            ensureSelectionIsValid(entries: entries)
        }
        .onDisappear {
            AppDelegate.shared?.setDockVisible(false)
        }
        .onChange(of: entries) { _, newEntries in
            ensureSelectionIsValid(entries: newEntries)
        }
        .onChange(of: selection) { _, _ in
            isEditingSelection = false
        }
        .onChange(of: isEditModeEnabled) { _, newValue in
            if newValue == false {
                isEditingSelection = false
            }
        }
        .onChange(of: isTestEditsEnabled) { _, newValue in
            if newValue == false {
                testOverrides.removeAll()
                isEditingSelection = false
            }
        }
        .onReceive(timer) { _ in
            if isEditModeEnabled || isEditingSelection {
                return
            }
            updater.updateBatteryInfo(modelContext: modelContext)
        }
    }

    private var totalCycles: Int {
        entries.reduce(0) { total, entry in
            total + (overrideValue(for: entry)?.cycles ?? entry.cycles)
        }
    }

    private var totalRawCycles: Double {
        entries.reduce(0) { total, entry in
            total + (overrideValue(for: entry)?.rawCycles ?? entry.rawCycles)
        }
    }

    private var totalMahUsed: Double {
        entries.reduce(0) { total, entry in
            total + (overrideValue(for: entry)?.totalMahUsed ?? entry.totalMahUsed)
        }
    }

    private var totalTimeOnBattery: Double {
        entries.reduce(0) { total, entry in
            total + (overrideValue(for: entry)?.timeOnBattery ?? entry.timeOnBattery)
        }
    }

    private var totalTimePluggedIn: Double {
        entries.reduce(0) { total, entry in
            total + (overrideValue(for: entry)?.timePluggedIn ?? entry.timePluggedIn)
        }
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

    private func overrideValue(for entry: DailyCycle) -> DailyCycleOverride? {
        guard isTestEditsEnabled else { return nil }
        return testOverrides[entry.id]
    }

    private func ensureSelectionIsValid(entries: [DailyCycle]) {
        guard entries.isEmpty == false else {
            selection = nil
            return
        }

        if let selection, entries.contains(where: { $0.id == selection.id }) {
            return
        }

        selection = entries.first
    }
}

private struct DailyStatsDetailView: View {
    let entry: DailyCycle
    let isEditing: Bool
    let isTestEditsEnabled: Bool
    let override: DailyCycleOverride?
    let onSaveOverride: (DailyCycleOverride) -> Void
    @State private var draftDate = Date()
    @State private var draftCycles = 0
    @State private var draftRawCycles = 0.0
    @State private var draftTotalMahUsed = 0.0
    @State private var draftTimeOnBattery = 0.0
    @State private var draftTimePluggedIn = 0.0
    @State private var editMessage: String?
    @Environment(\.modelContext) private var modelContext
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        let displayDate = override?.date ?? entry.date
        let displayCycles = override?.cycles ?? entry.cycles
        let displayRawCycles = override?.rawCycles ?? entry.rawCycles
        let displayTotalMahUsed = override?.totalMahUsed ?? entry.totalMahUsed
        let displayTimeOnBattery = override?.timeOnBattery ?? entry.timeOnBattery
        let displayTimePluggedIn = override?.timePluggedIn ?? entry.timePluggedIn

        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                DatePicker("Date", selection: $draftDate, displayedComponents: .date)
                HStack {
                    Text("Cycles Gained")
                    Spacer()
                    TextField("", value: $draftCycles, format: .number)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Raw Cycles (mAh)")
                    Spacer()
                    TextField("", value: $draftRawCycles, format: .number)
                        .frame(width: 140)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Total mAh Used")
                    Spacer()
                    TextField("", value: $draftTotalMahUsed, format: .number)
                        .frame(width: 140)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Time on Battery (sec)")
                    Spacer()
                    TextField("", value: $draftTimeOnBattery, format: .number)
                        .frame(width: 140)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Time Plugged In (sec)")
                    Spacer()
                    TextField("", value: $draftTimePluggedIn, format: .number)
                        .frame(width: 140)
                        .multilineTextAlignment(.trailing)
                }
                Button("Save Changes") {
                    saveEdits()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(formatDate(displayDate))
                    .font(.title2)
                    .bold()
                    .scrollTargetLayout(isEnabled: true)

                StatRow(label: "Cycles Gained", value: "\(displayCycles)")
                StatRow(label: "Raw Cycles (mAh)", value: formatDecimal(displayRawCycles))
                StatRow(label: "Total mAh Used", value: formatDecimal(displayTotalMahUsed))
                StatRow(label: "Time on Battery", value: formatDuration(displayTimeOnBattery))
                StatRow(label: "Time Plugged In", value: formatDuration(displayTimePluggedIn))
            }

            DisclosureGroup("Cycle Breakdown") {
                if entry.cycleBreakdowns.isEmpty {
                    Text("No cycle breakdown yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cycleBreakdowns) { breakdown in
                        HStack {
                            Text(cycleBreakdownLabel(for: breakdown))
                            Spacer()
                            Text("\(formatDecimal(breakdown.mahUsed)) mAh")
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            loadDraft()
        }
        .onChange(of: entry.id) { _, _ in
            loadDraft()
        }
        .alert("Edit Cycle", isPresented: Binding(
            get: { editMessage != nil },
            set: { newValue in
                if newValue == false {
                    editMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editMessage ?? "")
        }
    }

    private func loadDraft() {
        let current = override
        draftDate = current?.date ?? entry.date
        draftCycles = current?.cycles ?? entry.cycles
        draftRawCycles = current?.rawCycles ?? entry.rawCycles
        draftTotalMahUsed = current?.totalMahUsed ?? entry.totalMahUsed
        draftTimeOnBattery = current?.timeOnBattery ?? entry.timeOnBattery
        draftTimePluggedIn = current?.timePluggedIn ?? entry.timePluggedIn
    }

    private func saveEdits() {
        let normalizedDate = Calendar.current.startOfDay(for: draftDate)
        if isTestEditsEnabled {
            onSaveOverride(DailyCycleOverride(
                date: normalizedDate,
                cycles: draftCycles,
                rawCycles: draftRawCycles,
                totalMahUsed: draftTotalMahUsed,
                timeOnBattery: draftTimeOnBattery,
                timePluggedIn: draftTimePluggedIn
            ))
            editMessage = "Test edit applied (not saved)."
            return
        }

        entry.date = normalizedDate
        entry.cycles = draftCycles
        entry.rawCycles = draftRawCycles
        entry.totalMahUsed = draftTotalMahUsed
        entry.timeOnBattery = draftTimeOnBattery
        entry.timePluggedIn = draftTimePluggedIn

        do {
            try modelContext.save()
            if Calendar.current.isDateInToday(entry.date),
               let currentCycleCount = getBatteryCycleCount() {
                let todayKey = Self.dayFormatter.string(from: entry.date)
                let baseline = max(0, currentCycleCount - draftCycles)
                let defaults = UserDefaults.standard
                defaults.set(todayKey, forKey: "cyclesBaselineDate")
                defaults.set(baseline, forKey: "cyclesBaselineCount")
            }
            editMessage = "Changes saved."
        } catch {
            editMessage = "Failed to save changes: \(error.localizedDescription)"
        }
    }

    private var cycleBreakdowns: [CycleBreakdown] {
        entry.cycleBreakdowns.sorted { $0.index < $1.index }
    }

    private func cycleBreakdownLabel(for breakdown: CycleBreakdown) -> String {
        if breakdown.isPartial {
            return "Cycle \(breakdown.index) (Partial - \(formatPercent(breakdown.completionPercent)))"
        }
        return "Cycle \(breakdown.index)"
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

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.2f%%", value)
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

private struct DailyCycleOverride: Hashable {
    let date: Date
    let cycles: Int
    let rawCycles: Double
    let totalMahUsed: Double
    let timeOnBattery: Double
    let timePluggedIn: Double
}

#Preview {
    HistoryView()
}
