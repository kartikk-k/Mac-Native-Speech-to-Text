//
//  MenuBarView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch appState.phase {
            case .listening:
                Text("Listening...")
                    .font(.headline)
            case .cancelPending:
                Text("Cancelling — tap Continue to keep recording")
                    .font(.body)
            case .processing:
                Text("Processing...")
                    .font(.headline)
            case .cleaning:
                Text("Improving...")
                    .font(.headline)
            case .failed:
                Text("Transcription failed — tap the pill to retry")
                    .font(.body)
                    .foregroundStyle(.orange.opacity(0.8))
            case .cleanupFailed:
                Text(appState.cleanupFailureReason ?? "Cleanup failed")
                    .font(.body)
                    .foregroundStyle(.orange.opacity(0.8))
            case .hidden, .permissionDenied:
                Text("Hold \(Image(systemName: "globe")) (Fn) to dictate")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(8)

        Divider()

        Button("Open App...") {
            appState.onShowMainWindow?()
        }

        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("[MenuBar] Launch at login error: \(error)")
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Button("Setup Permissions...") {
            appState.onShowMainWindow?()
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

#Preview("Menu Bar") {
    MenuBarView()
        .environmentObject(AppState())
        .frame(width: 240)
}
