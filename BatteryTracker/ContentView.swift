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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cycleCount = viewModel.cycleCount,
               let mahToNextCycle = viewModel.mahToNextCycle,
               let maxCapacityMah = viewModel.maxCapacityMah,
               maxCapacityMah > 0 {
                let percentComplete = (1.0 - (Double(mahToNextCycle) / Double(maxCapacityMah))) * 100
                let progressPercent = (Double(cycleCount) / 1000.0) * 100.0
                Text("Cycles: \(cycleCount) (\(String(format: "%.2f", progressPercent))%)")
                    .font(.headline)
                    .bold()
                Text("Cycle Completion: \(String(format: "%.2f", percentComplete))%")
                    .font(.headline)
                    .bold()
                
            } else {
                Text(viewModel.cycleCount.map(String.init) ?? "—")
                    .font(.largeTitle)
                    .bold()
            }
            Text("Battery Health: \(viewModel.rawBatteryHealthPercent) | \(viewModel.officialBatteryHealthPercent.map { "\($0)%" } ?? "—") (\(viewModel.officialBatteryHealthText))")
                .font(.subheadline)
            
            if let currentCapacityMah = viewModel.currentCapacityMah,
               let maxCapacityMah = viewModel.maxCapacityMah,
               let designCapacityMah = viewModel.designCapacityMah {
                Text("Capacity: \(currentCapacityMah)/\(maxCapacityMah) (\(designCapacityMah)) mAh")
                    .font(.subheadline)
            } else {
                Text("Capacity: Unknown")
                    .font(.subheadline)
            }

            if let cyclesToday = viewModel.cyclesToday {
                Text("Cycles Today: \(cyclesToday)")
                    .font(.subheadline)
            } else {
                Text("Cycles Today: —")
                    .font(.subheadline)
            }

            Text(viewModel.timeRemainingText)
                .font(.subheadline)

            if let cyclesPerDayNeeded = viewModel.cyclesPerDayNeeded {
                let roundedUp = Int(ceil(cyclesPerDayNeeded))
                Text("Cycles Per Day by Deadline: \(roundedUp) (\(viewModel.formatDecimal(cyclesPerDayNeeded)))")
                    .font(.subheadline)
            } else {
                Text("Cycles Per Day by Deadline: —")
                    .font(.subheadline)
            }

            if let mahToNextCycle = viewModel.mahToNextCycle {
                Text("mAh to Next Cycle: \(mahToNextCycle)")
                    .font(.subheadline)
            } else {
                Text("mAh to Next Cycle: —")
                    .font(.subheadline)
            }

            Divider()

            Button("History") {
                showHistoryWindow()
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
        .padding()
        .frame(width: 260)
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
}

#Preview {
    ContentView()
}

