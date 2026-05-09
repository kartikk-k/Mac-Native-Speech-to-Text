//
//  SettingsTabView.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI
import ServiceManagement
import Sparkle

struct SettingsTabView: View {
    @Environment(PermissionManager.self) private var permissionManager
    var updaterManager: UpdaterManager?
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var showIndicator: Bool = UserDefaults.standard.object(forKey: "setting_showIndicator") as? Bool ?? true
    @State private var onDeviceOnly: Bool = UserDefaults.standard.object(forKey: "setting_onDeviceOnly") as? Bool ?? true
    @State private var selectedLanguage: String = "en-US"
    @State private var selectedProvider: TranscriptionProviderID = {
        let raw = UserDefaults.standard.string(forKey: SpeechManager.providerDefaultsKey) ?? TranscriptionProviderID.appleNative.rawValue
        return TranscriptionProviderID(rawValue: raw) ?? .appleNative
    }()
    @StateObject private var modelManager = ModelManager()

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)

                // MARK: General
                dsCard {
                    HStack {
                        Text("Launch at login")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white)
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update launch at login: \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                }

                dsSectionHeader(icon: "mic.fill", title: "Recognition")

                dsCard {
                    dsPickerRow(title: "Language", value: selectedLanguage == "en-US" ? "English (US)" : selectedLanguage, options: ["English (US)"]) { _ in }

                    dsDivider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hotkey")
                                .font(.system(size: 13.5))
                                .foregroundStyle(.white)
                            Text("Hold to record, release to transcribe")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.40))
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text("Fn")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                }

                // MARK: Transcription Engine
                dsSectionHeader(icon: "waveform.badge.magnifyingglass", title: "Transcription Engine")

                dsCard {
                    Text("Choose which engine converts your speech to text. Apple Native is built into macOS. Other models are downloaded once and run locally on your Mac.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.45))

                    dsDivider()

                    engineRow(
                        title: TranscriptionProviderID.appleNative.displayName,
                        subtitle: "Built-in macOS speech recognition. Always available.",
                        isSelected: selectedProvider == .appleNative,
                        statusBadge: nil,
                        select: { setProvider(.appleNative) }
                    )

                    ForEach(ModelRegistry.availableModels) { model in
                        dsDivider()
                        modelRow(model: model)
                    }
                }

                dsSectionHeader(icon: "lock.shield", title: "Permissions")

                dsCard {
                    settingsPermissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        granted: permissionManager.microphoneGranted,
                        action: { permissionManager.requestMicrophone() }
                    )
                    dsDivider()
                    settingsPermissionRow(
                        icon: "waveform",
                        title: "Speech Recognition",
                        granted: permissionManager.speechRecognitionGranted,
                        action: { permissionManager.requestSpeechRecognition() }
                    )
                    dsDivider()
                    settingsPermissionRow(
                        icon: "lock.shield",
                        title: "Accessibility",
                        granted: permissionManager.accessibilityGranted,
                        action: { permissionManager.requestAccessibility() }
                    )
                }
                .onAppear {
                    permissionManager.checkAll()
                    permissionManager.startPollingAccessibility()
                    modelManager.refreshAllStates()
                }
                .onDisappear {
                    permissionManager.stopPollingAccessibility()
                }

                dsSectionHeader(icon: "info.circle", title: "About")

                dsCard {
                    HStack {
                        Text("Version")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(appVersion)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }

                    dsDivider()

                    HStack {
                        Text("Check for updates automatically")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { updaterManager?.automaticallyChecksForUpdates ?? true },
                            set: { updaterManager?.automaticallyChecksForUpdates = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }

                    dsDivider()

                    HStack(spacing: 10) {
                        dsCardButton(icon: "arrow.triangle.2.circlepath", label: "Check for Updates") {
                            updaterManager?.checkForUpdates()
                        }

                        dsCardButton(icon: "arrow.up.right.square", label: "View on GitHub") {
                            if let url = URL(string: "https://github.com/kartikk-k/Echotype-Mac") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                // Footer
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.25))
                        Text("Echotype Mac - v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.30))
                    }
                    Text("Open-source, on-device speech recognition for macOS.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.20))
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Engine row helpers

    private func setProvider(_ provider: TranscriptionProviderID) {
        selectedProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: SpeechManager.providerDefaultsKey)
        NotificationCenter.default.post(name: SpeechManager.providerChangedNotification, object: nil)
    }

    @ViewBuilder
    private func modelRow(model: ModelInfo) -> some View {
        let state = modelManager.state(for: model.id)
        let installed = modelManager.isInstalled(model.id)
        let canSelect = installed
        let badge: String? = {
            switch state {
            case .installed: return "Installed"
            case .downloading: return "Downloading"
            case .failed: return "Failed"
            case .notInstalled: return nil
            }
        }()

        VStack(alignment: .leading, spacing: 8) {
            engineRow(
                title: model.displayName,
                subtitle: "\(model.provider) · \(model.description)",
                isSelected: canSelect && selectedProvider == model.providerID,
                statusBadge: badge,
                select: {
                    if canSelect { setProvider(model.providerID) }
                }
            )

            HStack(spacing: 8) {
                switch state {
                case .notInstalled:
                    dsCardButton(icon: "arrow.down.circle", label: "Download (\(formatBytes(model.totalApproximateBytes)))") {
                        modelManager.install(model)
                    }
                case .downloading(let progress, let currentFile):
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 220)
                        Text("\(Int(progress * 100))% · \(currentFile)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Spacer()
                        dsCardButton(icon: "xmark.circle", label: "Cancel") {
                            modelManager.cancelDownload(modelID: model.id)
                        }
                    }
                case .installed:
                    dsCardButton(icon: "trash", label: "Remove") {
                        modelManager.uninstall(model)
                        if selectedProvider == model.providerID {
                            setProvider(.appleNative)
                        }
                    }
                    if let url = model.licenseURL {
                        dsCardButton(icon: "doc.text", label: "License (\(model.licenseName))") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                case .failed(let reason):
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.85))
                    dsCardButton(icon: "arrow.clockwise", label: "Retry") {
                        modelManager.install(model)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func engineRow(title: String,
                           subtitle: String,
                           isSelected: Bool,
                           statusBadge: String?,
                           select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.4))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white)
                        if let badge = statusBadge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func settingsPermissionRow(icon: String, title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(.white)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

#Preview("Settings") {
    SettingsTabView()
        .environment(PermissionManager())
        .frame(width: 600, height: 500)
}
