//
//  BatteryTrackerApp.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/17/26.
//

import Foundation
import SwiftUI
import SwiftData

@main
struct BatteryTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        MenuBarExtra("42 cycles/day", systemImage: "battery.100") {
            ContentView()
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)

        Window("History", id: "history") {
            HistoryView()
                .modelContainer(container)
        }

        Window("Settings", id: "settings") {
            SettingsView()
        }

        Window("Dev Tools", id: "devTools") {
            DevToolsView()
                .modelContainer(container)
        }
    }
}

private extension BatteryTrackerApp {

    static func makeContainer() -> ModelContainer {
        let schema = Schema([DailyCycle.self, CycleBreakdown.self])
        let storeURL = hardOverrideStoreURL()
        let configuration = ModelConfiguration(
            "BatteryTracker",
            schema: schema,
            url: storeURL
        )

        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            if container.configurations.first?.url.path == "/dev/null" {
                fatalError("SwiftData resolved store to /dev/null.\nStore: \(storeURL.path)")
            }
            return container
        } catch {
            fatalError("Failed to create SwiftData container: \(error)\\nStore: \(storeURL.path)")
        }
    }

    static func persistentStoreURL() -> URL {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("BatteryTracker", isDirectory: true)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return fileManager.temporaryDirectory.appendingPathComponent("BatteryTracker.store")
        }

        return directory.appendingPathComponent("BatteryTracker.store")
    }

    static func hardOverrideStoreURL() -> URL {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("BatteryTracker", isDirectory: true)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return fileManager.temporaryDirectory.appendingPathComponent("BatteryTracker.store")
        }

        return directory.appendingPathComponent("BatteryTracker.store")
    }

}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?
    private var allowQuit = false

    override init() {
        super.init()
        Self.shared = self
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowQuit {
            return .terminateNow
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        return .terminateCancel
    }

    func requestQuit() {
        allowQuit = true
        NSApplication.shared.terminate(nil)
    }

    func hideDockIcon() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func setDockVisible(_ visible: Bool) {
        NSApplication.shared.setActivationPolicy(visible ? .regular : .accessory)
        if visible {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
