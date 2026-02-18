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
    private static let migrationFlagKey = "didMigrateCycleHistoryToSwiftData"
    private static let legacyHistoryKey = "cyclesHistory"
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
        Self.migrateLegacyHistoryIfNeeded(container: container)
    }

    var body: some Scene {
        MenuBarExtra("42 cycles/day", systemImage: "battery.100") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(container)

        Window("History", id: "history") {
            HistoryView()
        }
        .modelContainer(container)
    }
}

private extension BatteryTrackerApp {

    static func makeContainer() -> ModelContainer {
        let schema = Schema([DailyCycle.self])

        let storeURL = persistentStoreURL()
        let configuration = ModelConfiguration("BatteryTracker", schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            deleteStore(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Failed to create SwiftData container: \(error)")
            }
        }
    }

    static func persistentStoreURL() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = (supportDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("BatteryTracker", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return directory.appendingPathComponent("BatteryTracker.store")
        }

        return directory.appendingPathComponent("BatteryTracker.store")
    }

    static func deleteStore(at url: URL) {
        let fileManager = FileManager.default
        let relatedExtensions = ["", "-shm", "-wal"]

        for suffix in relatedExtensions {
            let target = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: target.path) {
                try? fileManager.removeItem(at: target)
            }
        }
    }

    static func migrateLegacyHistoryIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: migrationFlagKey) == false else {
            return
        }

        let legacyHistory = defaults.dictionary(forKey: legacyHistoryKey) as? [String: Int] ?? [:]
        guard legacyHistory.isEmpty == false else {
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        let context = ModelContext(container)
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        for (key, cycles) in legacyHistory {
            guard let parsedDate = formatter.date(from: key) else {
                continue
            }

            let date = Calendar.current.startOfDay(for: parsedDate)
            let descriptor = FetchDescriptor<DailyCycle>(
                predicate: #Predicate { $0.date == date }
            )

            if let existing = try? context.fetch(descriptor).first {
                existing.cycles = cycles
            } else {
                context.insert(DailyCycle(date: date, cycles: cycles))
            }
        }

        try? context.save()
        defaults.set(true, forKey: migrationFlagKey)
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

