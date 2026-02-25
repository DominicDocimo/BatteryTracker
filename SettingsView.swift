//
//  SettingsView.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/24/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("isDevModeEnabled") private var isDevModeEnabled = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Dev Mode", isOn: $isDevModeEnabled)
                .toggleStyle(.switch)
            if isDevModeEnabled {
                Button("Dev Tools") {
                    openWindow(id: "devTools")
                }
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 260, minHeight: 120)
    }
}

#Preview {
    SettingsView()
}
