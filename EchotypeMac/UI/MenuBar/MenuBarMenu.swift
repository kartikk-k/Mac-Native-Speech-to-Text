//
//  MenuBarMenu.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  The menu bar dropdown. Quick toggles (Launch at Login, Fix Grammar), a Recent
//  submenu of the last few clips (click to copy the transcript), and shortcuts
//  into Settings / the app. Kept as plain SwiftUI menu items so it renders as a
//  native NSMenu inside MenuBarExtra.
//

import SwiftUI
import ServiceManagement
import AppKit

struct MenuBarMenu: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var historyStore: HistoryStore

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    // Mirror the persisted grammar setting so the toggle reflects/updates it.
    @AppStorage("setting_fixGrammar") private var fixGrammar = true

    var body: some View {
        // Current status line.
        Text(statusText)

        Divider()

        // Recent — last 5 clips; clicking copies that transcript to the clipboard.
        Menu("Recent") {
            let recent = Array(historyStore.entries.prefix(5))
            if recent.isEmpty {
                Text("No recent transcriptions").disabled(true)
            } else {
                ForEach(recent) { entry in
                    Button(recentLabel(entry)) {
                        copyToClipboard(entry.finalText)
                    }
                    .disabled(entry.failed || entry.finalText.isEmpty)
                }
            }
        }

        Button("Open History…") {
            appState.requestedTab = .history
            appState.onShowMainWindow?()
        }

        Divider()

        // Quick settings.
        Toggle("Fix Grammar", isOn: $fixGrammar)

        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Button("Settings…") {
            appState.requestedTab = .settings
            appState.onShowMainWindow?()
        }

        Divider()

        Button("Open App…") {
            appState.onShowMainWindow?()
        }

        Button("Quit Echotype") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        switch appState.phase {
        case .listening: return "Listening…"
        case .cancelPending: return "Cancelling — tap Continue to keep recording"
        case .processing: return "Transcribing…"
        case .cleaning: return "Improving…"
        case .failed: return "Last capture failed — retry in History"
        case .cleanupFailed: return appState.cleanupFailureReason ?? "Cleanup failed"
        case .hidden, .permissionDenied: return "Hold Fn to dictate"
        }
    }

    /// A short one-line label for a recent entry: time + a text snippet.
    private func recentLabel(_ entry: HistoryEntry) -> String {
        let time = entry.createdAt.formatted(date: .omitted, time: .shortened)
        if entry.failed { return "\(time) — (failed)" }
        let text = entry.finalText.replacingOccurrences(of: "\n", with: " ")
        let snippet = text.count > 40 ? String(text.prefix(40)) + "…" : text
        return "\(time) — \(snippet)"
    }

    private func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
