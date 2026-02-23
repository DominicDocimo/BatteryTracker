//
//  ContentView.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/17/26.
//




import AppKit
import SwiftData
import SwiftUI

@MainActor
private let appDelegate = AppDelegate.shared

struct ContentView: View {
    @State private var viewModel = BatteryStatusViewModel()
    @State private var usesClockwiseProgression = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    private let ringLineWidth: CGFloat = 6
    private let showsAddCycleTodayButton = false
    private let showsOpenInFinderButton = false
    private let showsOpenPathToDatabaseButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cycleCount = viewModel.cycleCount,
               let mahToNextCycle = viewModel.mahToNextCycle,
               let designCapacityMah = viewModel.designCapacityMah,
               designCapacityMah > 0 {
                let dischargedSinceLastCycle = max(0, Double(designCapacityMah - mahToNextCycle))
                let rawPercent = (dischargedSinceLastCycle / Double(designCapacityMah)) * 100
                let percentComplete = min(100, max(0, rawPercent))
                let progressPercent = (Double(cycleCount) / 1000.0) * 100.0
                let cyclesTodayPercent = cyclesTodayProgressPercent()
                let cyclesTodayDetail = cyclesTodayDetailText()

                HStack(spacing: 18) {
                    ProgressRingView(
                        title: "Cycles",
                        subtitle: "To 1,000",
                        valueText: "\(String(format: "%.2f", progressPercent))%",
                        detailLines: [
                            "\(formatInt(cycleCount))/1,000",
                            timeUntilJuneFirstText()
                        ],
                        progress: min(1, max(0, progressPercent / 100.0)),
                        accent: progressColor(for: progressPercent),
                        lineWidth: ringLineWidth,
                        usesClockwiseProgression: usesClockwiseProgression
                    )
                    ProgressRingView(
                        title: "Cycle",
                        subtitle: "Completion",
                        valueText: "\(String(format: "%.2f", percentComplete))%",
                        detailLines: cycleCompletionDetailLines(),
                        progress: percentComplete / 100.0,
                        accent: progressColor(for: percentComplete),
                        lineWidth: ringLineWidth,
                        usesClockwiseProgression: usesClockwiseProgression
                    )
                    ProgressRingView(
                        title: "Cycles",
                        subtitle: "Today",
                        valueText: cyclesTodayPercent.map { "\(String(format: "%.2f", $0))%" } ?? "—",
                        detailLines: cyclesTodayDetailLines(baseText: cyclesTodayDetail),
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
                Text("Cycles Per Day by Deadline: \(roundedUp) (\(viewModel.formatDecimal(cyclesPerDayNeeded)))")
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
            if let mahToNextCycle = viewModel.mahToNextCycle {
                Text("mAh to Next Cycle: \(mahToNextCycle)")
                    .font(.subheadline)
            } else {
                Text("mAh to Next Cycle: —")
                    .font(.subheadline)
            }
            Text(viewModel.timeToNextCycleText)
                .font(.subheadline)

            Divider()

            Button("History") {
                showHistoryWindow()
            }
            Button(usesClockwiseProgression ? "Use Counterclockwise Progression" : "Use Clockwise Progression") {
                usesClockwiseProgression.toggle()
            }
            if showsAddCycleTodayButton {
                Button("Add Cycle Today") {
                    viewModel.incrementTodayCycle(modelContext: modelContext)
                }
            }
            if showsOpenInFinderButton {
                Button("Open in Finder") {
                    revealAppInFinder()
                }
            }
            if showsOpenPathToDatabaseButton {
                Button("Open Path to Database") {
                    viewModel.revealStoreLocation(modelContext: modelContext)
                }
            }
/*
            Button("Show Store Location") {
                viewModel.revealStoreLocation(modelContext: modelContext)
            }
*/
            Button("Quit") {
                appDelegate?.requestQuit()
            }
        }
        .padding(.top, 6)
        .padding(.leading, 7)
        .padding(.bottom, 10)
        .frame(width: 320)
        .alert("SwiftData Store Location", isPresented: Binding(
            get: { viewModel.storeLocationMessage != nil },
            set: { newValue in
                if newValue == false {
                    viewModel.storeLocationMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.storeLocationMessage ?? "Unavailable")
        }
        .task {
            viewModel.updateBatteryInfo(modelContext: modelContext)
            await viewModel.refreshOfficialBatteryHealthPercent()
            while !Task.isCancelled {
                let interval = viewModel.refreshIntervalSeconds()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                viewModel.updateBatteryInfo(modelContext: modelContext)
                await viewModel.refreshOfficialBatteryHealthPercent()
            }
        }
    }

    private func showHistoryWindow() {
        if let window = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "history" || $0.title == "History"
        }) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            openWindow(id: "history")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApplication.shared.windows.first(where: {
                    $0.identifier?.rawValue == "history" || $0.title == "History"
                }) {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }

    private func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func progressColor(for percent: Double) -> Color {
        switch percent {
        case ..<0:
            return .red
        case 0...35:
            return .red
        case 35.000001...75:
            return .yellow
        default:
            return .green
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

        let percent = (Double(cyclesToday) / Double(roundedUp)) * 100.0
        return max(0, percent)
    }

    private func cyclesTodayDetailText() -> String {
        let cyclesToday = viewModel.cyclesToday ?? 0
        if let cyclesPerDayNeeded = viewModel.cyclesPerDayNeeded {
            let roundedUp = Int(ceil(cyclesPerDayNeeded))
            return "\(formatInt(cyclesToday))/\(formatInt(roundedUp))"
        }
        return "\(formatInt(cyclesToday))/—"
    }

    private func cycleCompletionDetailLines() -> [String] {
        guard let mahToNextCycle = viewModel.mahToNextCycle,
              let designCapacityMah = viewModel.designCapacityMah,
              designCapacityMah > 0 else {
            return ["—"]
        }

        let discharged = max(0, designCapacityMah - mahToNextCycle)
        var lines = ["\(formatInt(discharged))/\(formatInt(designCapacityMah)) mAh"]

        if let currentCapacityMah = viewModel.currentCapacityMah,
           let maxCapacityMah = viewModel.maxCapacityMah {
            lines.append("\(formatInt(currentCapacityMah))/\(formatInt(maxCapacityMah)) mAh")
        }

        return lines
    }

    private func cyclesTodayDetailLines(baseText: String) -> [String] {
        var lines = [baseText]

        guard let designCapacityMah = viewModel.designCapacityMah,
              let cyclesPerDayNeeded = viewModel.cyclesPerDayNeeded else {
            return lines
        }

        let roundedUp = Int(ceil(cyclesPerDayNeeded))
        guard roundedUp > 0 else {
            return lines
        }

        let targetMah = Double(designCapacityMah * roundedUp)
        let usedMah = max(0, viewModel.totalMahUsedToday ?? 0)
        let remaining = targetMah - usedMah
        if remaining >= 0 {
            lines.append("\(formatInt(Int(remaining.rounded()))) mAh Left")
        } else {
            lines.append("\(formatInt(Int((-remaining).rounded()))) mAh Over")
        }

        return lines
    }


    private func timeUntilJuneFirstText() -> String {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 1

        guard let targetDate = Calendar.current.date(from: components) else {
            return "- Days"
        }

        let today = Calendar.current.startOfDay(for: Date())
        let daysRemaining = Calendar.current.dateComponents([.day], from: today, to: targetDate).day ?? 0
        if daysRemaining <= 0 {
            return "Today"
        }

        let dayLabel = daysRemaining == 1 ? "Day" : "Days"
        return "\(daysRemaining) \(dayLabel) "
    }

    private func formatInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let subtitle {
                Text(subtitle)
                    .font(.headline)
                    .bold()
                    .foregroundStyle(.white)
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
            ForEach(detailLines, id: \.self) { detailText in
                Text(detailText)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: 92)
    }
}

#Preview {
    ContentView()
}
