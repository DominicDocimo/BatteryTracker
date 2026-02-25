//
//  DevToolsView.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/24/26.
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DevToolsView: View {
    @State private var viewModel = BatteryStatusViewModel()
    @State private var devToolsMessage: String?
    @AppStorage("isDevModeEnabled") private var isDevModeEnabled = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Open Path to Database") {
                viewModel.revealStoreLocation(modelContext: modelContext)
            }
            Button("Export Backup") {
                exportBackup()
            }
            Button("Restore From Backup") {
                restoreBackup()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Store Location")
                    .font(.headline)
                Text(storeURLDescription())
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 360, minHeight: 160)
        .alert("Dev Tools", isPresented: Binding(
            get: { devToolsMessage != nil },
            set: { newValue in
                if newValue == false {
                    devToolsMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(devToolsMessage ?? "Done.")
        }
    }

    private func storeURLDescription() -> String {
        if let url = modelContext.container.configurations.first?.url {
            return url.path
        }
        return "Unknown"
    }

    private func exportBackup() {
        let panel = NSOpenPanel()
        panel.title = "Export Backup"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return
        }

        let needsStop = url.startAccessingSecurityScopedResource()
        defer {
            if needsStop {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let daily = try modelContext.fetch(FetchDescriptor<DailyCycle>())
            try CSVBackupService.exportBackup(dailyCycles: daily, to: url)
            devToolsMessage = "Exported backup to \(url.path)"
        } catch {
            devToolsMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.title = "Restore From Backup"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.prompt = "Restore"

        let response = panel.runModal()
        guard response == .OK else {
            return
        }

        var urls: [URL] = []
        for url in panel.urls {
            _ = url.startAccessingSecurityScopedResource()
            urls.append(url)
        }
        defer {
            for url in urls {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let result = try CSVBackupService.restoreBackup(urls: urls, modelContext: modelContext)
            devToolsMessage = """
            Restored \(result.insertedDaily) daily rows and \(result.insertedBreakdown) breakdown rows.
            Skipped \(result.skippedDaily) daily rows and \(result.skippedBreakdown) breakdown rows.
            """
        } catch {
            devToolsMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    DevToolsView()
}
