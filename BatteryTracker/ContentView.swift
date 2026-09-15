//
//  ContentView.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/17/26.
//

import AppKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var viewModel = BatteryStatusViewModel()
    @State private var usesClockwiseProgression = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    private let ringLineWidth: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cycleCount = viewModel.cycleCount,
               let mahToNextCycle = viewModel.mahToNextCycle,
               let designCapacityMah = viewModel.designCapacityMah,
               designCapacityMah > 0 {
                let dischargedSinceLastCycle = max(0, Double(designCapacityMah - mahToNextCycle))
                let percentComplete = min(100, max(0, (dischargedSinceLastCycle / Double(designCapacityMah)) * 100))
                let progressPercent = (Double(cycleCount) / Double(BatteryGoal.targetCycles)) * 100.0
                let cyclesTodayPercent = cyclesTodayProgressPercent()

                HStack(spacing: 18) {
                    ProgressRingView(
                        title: "Cycles",
                        subtitle: "To \(Formatting.integer(BatteryGoal.targetCycles))",
                        valueText: "\(Formatting.decimal(progressPercent))%",
                        detailLines: [
                            "\(Formatting.integer(cycleCount))/\(Formatting.integer(BatteryGoal.targetCycles))",
                            daysUntilDeadlineText()
                        ],
                        progress: min(1, max(0, progressPercent / 100.0)),
                        accent: progressColor(for: progressPercent),
                        lineWidth: ringLineWidth,
                        usesClockwiseProgression: usesClockwiseProgression
                    )
                    ProgressRingView(
                        title: "Cycle",
                        subtitle: "Completion",
                        valueText: "\(Formatting.decimal(percentComplete))%",
                        detailLines: cycleCompletionDetailLines(),
                        progress: percentComplete / 100.0,
                        accent: progressColor(for: percentComplete),
                        lineWidth: ringLineWidth,
                        usesClockwiseProgression: usesClockwiseProgression
                    )
                    ProgressRingView(
                        title: "Cycles",
                        subtitle: "Today",
                        valueText: cyclesTodayPercent.map { "\(Formatting.decimal($0))%" } ?? "—",
                        detailLines: cyclesTodayDetailLines(),
                        progress: max(0, (cyclesTodayPercent ?? 0) / 100.0),
                        accent: progressColor(for: cyclesTodayPercent ?? 0),
                        lineWidth: ringLineWidth,
                        usesClockwiseProgression: usesClockwiseProgression
                    )
                }
                .frame(maxWidth: .infinity)

                Divider()
            } else {
                Text(viewModel.cycleCount.map(String.init) ?? "—")
                    .font(.largeTitle)
                    .bold()
            }

            Text("Battery")
                .font(.headline)
                .bold()
            Text("Raw Battery Health: \(viewModel.rawBatteryHealthPercent)")
                .font(.subheadline)
            Text("Official Battery Health: \(viewModel.officialBatteryHealthPercent.map { "\($0)%" } ?? "—") (\(viewModel.officialBatteryHealthText))")
                .font(.subheadline)
            if let cyclesPerDayNeeded = viewModel.cyclesPerDayNeeded {
                let roundedUp = Int(ceil(cyclesPerDayNeeded))
                Text("Cycles Per Day by Deadline: \(roundedUp) (\(Formatting.decimal(cyclesPerDayNeeded)))")
                    .font(.subheadline)
            } else {
                Text("Cycles Per Day by Deadline: —")
                    .font(.subheadline)
            }

            Divider()

            Text("Timing")
                .font(.headline)
                .bold()
            Text(viewModel.timeRemainingText)
                .font(.subheadline)
            Text(viewModel.timeToTenMinutesRemainingText)
                .font(.subheadline)
            Text("mAh to Next Cycle: \(viewModel.mahToNextCycle.map(String.init) ?? "—")")
                .font(.subheadline)
            Text(viewModel.timeToNextCycleText)
                .font(.subheadline)


            Divider()

            Button("History") {
                showHistoryWindow()
            }
            Button(usesClockwiseProgression ? "Use Counterclockwise Progression" : "Use Clockwise Progression") {
                usesClockwiseProgression.toggle()
            }
            Button("Quit") {
                AppDelegate.shared?.requestQuit()
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .frame(width: 320)
        .task {
            viewModel.updateBatteryInfo(modelContext: modelContext)
            await viewModel.refreshOfficialBatteryHealthPercent()
            while !Task.isCancelled {
                let interval = viewModel.refreshIntervalSeconds()
                try? await Task.sleep(for: .seconds(interval))
                viewModel.updateBatteryInfo(modelContext: modelContext)
                await viewModel.refreshOfficialBatteryHealthPercent()
            }
        }
    }

    private func showHistoryWindow() {
        openWindow(id: "history")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func progressColor(for percent: Double) -> Color {
        switch percent {
        case ...35:
            .red
        case ...75:
            .yellow
        default:
            .green
        }
    }

    private func cyclesTodayProgressPercent() -> Double? {
        guard let cyclesToday = viewModel.cyclesToday,
              let cyclesPerDayNeeded = viewModel.cyclesPerDayNeeded else {
            return nil
        }

        let roundedUp = Int(ceil(cyclesPerDayNeeded))
        guard roundedUp > 0 else {
            return nil
        }

        return max(0, (Double(cyclesToday) / Double(roundedUp)) * 100.0)
    }

    private func cycleCompletionDetailLines() -> [String] {
        guard let mahToNextCycle = viewModel.mahToNextCycle,
              let designCapacityMah = viewModel.designCapacityMah,
              designCapacityMah > 0 else {
            return ["—"]
        }

        let discharged = max(0, designCapacityMah - mahToNextCycle)
        var lines = ["\(Formatting.integer(discharged))/\(Formatting.integer(designCapacityMah)) mAh"]

        if let currentCapacityMah = viewModel.currentCapacityMah,
           let maxCapacityMah = viewModel.maxCapacityMah {
            lines.append("\(Formatting.integer(currentCapacityMah))/\(Formatting.integer(maxCapacityMah)) mAh")
        }

        return lines
    }

    private func cyclesTodayDetailLines() -> [String] {
        let cyclesToday = viewModel.cyclesToday ?? 0

        guard let cyclesPerDayNeeded = viewModel.cyclesPerDayNeeded else {
            return ["\(Formatting.integer(cyclesToday))/—"]
        }

        let roundedUp = Int(ceil(cyclesPerDayNeeded))
        var lines = ["\(Formatting.integer(cyclesToday))/\(Formatting.integer(roundedUp))"]

        guard let designCapacityMah = viewModel.designCapacityMah, roundedUp > 0 else {
            return lines
        }

        let targetMah = Double(designCapacityMah * roundedUp)
        let usedMah = max(0, viewModel.totalMahUsedToday ?? 0)
        let remaining = targetMah - usedMah
        if remaining >= 0 {
            lines.append("\(Formatting.integer(Int(remaining.rounded()))) mAh Left")
        } else {
            lines.append("\(Formatting.integer(Int((-remaining).rounded()))) mAh Over")
        }

        return lines
    }

    private func daysUntilDeadlineText() -> String {
        let today = Calendar.current.startOfDay(for: Date())
        guard let daysRemaining = BatteryGoal.daysUntilDeadline(from: today) else {
            return "— Days"
        }

        if daysRemaining <= 0 {
            return "Today"
        }

        return daysRemaining == 1 ? "1 Day" : "\(daysRemaining) Days"
    }
}

private struct ProgressRingView: View {
    let title: String
    let subtitle: String?
    let valueText: String
    let detailLines: [String]
    let progress: Double
    let accent: Color
    let lineWidth: CGFloat
    let usesClockwiseProgression: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.headline)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let subtitle {
                Text(subtitle)
                    .font(.headline)
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.25), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(x: usesClockwiseProgression ? 1 : -1, y: 1, anchor: .center)
                Text(valueText)
                    .font(.headline)
                    .foregroundStyle(accent)
            }
            .frame(width: 76, height: 76)
            ForEach(Array(detailLines.enumerated()), id: \.offset) { _, detailText in
                Text(detailText)
                    .font(.caption)
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: 92)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: DailyCycle.self, inMemory: true)
}
