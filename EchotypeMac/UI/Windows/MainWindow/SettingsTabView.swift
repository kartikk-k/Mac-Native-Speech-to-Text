//
//  SettingsTabView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI
import ServiceManagement
import Sparkle

struct SettingsTabView: View {
    @Environment(PermissionManager.self) private var permissionManager
    @EnvironmentObject private var appState: AppState
    var updaterManager: UpdaterManager?
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var showIndicator: Bool = UserDefaults.standard.object(forKey: "setting_showIndicator") as? Bool ?? true
    @State private var showMenuBarIcon: Bool = TranscriptionSettings.showMenuBarIcon
    @State private var hotkey: HotkeyBinding = TranscriptionSettings.hotkeyBinding
    @State private var onDeviceOnly: Bool = UserDefaults.standard.object(forKey: "setting_onDeviceOnly") as? Bool ?? true
    @State private var selectedLanguage: String = "en-US"
    @State private var transcriptionProvider: TranscriptionProvider = TranscriptionSettings.provider
    @State private var openAIKeyInput: String = TranscriptionSettings.openAIApiKey ?? ""
    @State private var openAIKeySaved: Bool = TranscriptionSettings.hasOpenAIKey
    @State private var fixGrammar: Bool = TranscriptionSettings.fixGrammar
    @State private var rephrase: Bool = TranscriptionSettings.rephrase
    
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

                    dsDivider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show menu bar icon")
                                .font(.system(size: 13.5))
                                .foregroundStyle(.white)
                            Text("The microphone icon and quick menu in the menu bar")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.40))
                        }
                        Spacer()
                        Toggle("", isOn: $showMenuBarIcon)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .onChange(of: showMenuBarIcon) { _, newValue in
                        TranscriptionSettings.showMenuBarIcon = newValue
                    }
                }

                dsSectionHeader(icon: "waveform.circle", title: "Transcription Engine")

                dsCard {
                    dsPickerRow(
                        title: "Engine",
                        value: transcriptionProvider.displayName,
                        options: TranscriptionProvider.allCases.map { $0.displayName }
                    ) { selected in
                        if let picked = TranscriptionProvider.allCases.first(where: { $0.displayName == selected }) {
                            transcriptionProvider = picked
                            TranscriptionSettings.provider = picked
                        }
                    }

                    if transcriptionProvider == .native {
                        Text("Uses Apple's built-in, on-device recognition. Fully private, works offline.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.40))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        dsDivider()

                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("OpenAI API Key")
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(.white)
                                Text("Sends your speech to OpenAI for transcription. Only the resulting text is returned — no audio is stored. Your key is kept securely in your Keychain.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.55))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                SecureField("sk-...", text: $openAIKeyInput)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.white.opacity(0.06))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                                            )
                                    )
                                    .onChange(of: openAIKeyInput) { _, _ in
                                        openAIKeySaved = false
                                    }

                                dsCardButton(icon: openAIKeySaved ? "checkmark" : "square.and.arrow.down",
                                             label: openAIKeySaved ? "Saved" : "Save") {
                                    TranscriptionSettings.openAIApiKey = openAIKeyInput
                                    openAIKeySaved = TranscriptionSettings.hasOpenAIKey
                                }
                            }

                            if !openAIKeySaved && !TranscriptionSettings.hasOpenAIKey {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.orange)
                                    Text("No API key yet — dictation falls back to the built-in macOS engine until you add one, so you're never left without transcription.")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Color.orange.opacity(0.9))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.orange.opacity(0.10))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
                                )
                            }
                        }
                    }
                }

                dsSectionHeader(icon: "text.badge.checkmark", title: "Text Cleanup")

                dsCard {
                    dsToggleRow(
                        icon: "checkmark.circle",
                        title: "Fix grammar",
                        subtitle: "Correct grammar and format lists as you dictate, keeping your meaning",
                        binding: $fixGrammar
                    )
                    .onChange(of: fixGrammar) { _, newValue in
                        TranscriptionSettings.fixGrammar = newValue
                    }

                    dsDivider()

                    dsToggleRow(
                        icon: "wand.and.stars",
                        title: "Rephrase",
                        subtitle: "Polish phrasing and flow for clearer writing (off by default)",
                        binding: $rephrase
                    )
                    .onChange(of: rephrase) { _, newValue in
                        TranscriptionSettings.rephrase = newValue
                    }

                    if (fixGrammar || rephrase) && !TranscriptionSettings.hasOpenAIKey {
                        Text("Cleanup uses OpenAI — add an API key above to enable it. Until then, text is inserted as transcribed.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                dsSectionHeader(icon: "mic.fill", title: "Recognition")

                dsCard {
                    //                    dsToggleRow(
                    //                        icon: "waveform",
                    //                        title: "Show Indicator Bar",
                    //                        subtitle: "Display the overlay pill while recording",
                    //                        binding: $showIndicator
                    //                    )
                    //                    .onChange(of: showIndicator) { _, newValue in
                    //                        UserDefaults.standard.set(newValue, forKey: "setting_showIndicator")
                    //                    }
                    //
                    //                    dsDivider()
                    //
                    //                    dsToggleRow(
                    //                        icon: "cpu",
                    //                        title: "On-device Only",
                    //                        subtitle: "Use on-device recognition, no data sent to Apple",
                    //                        binding: $onDeviceOnly
                    //                    )
                    //                    .onChange(of: onDeviceOnly) { _, newValue in
                    //                        UserDefaults.standard.set(newValue, forKey: "setting_onDeviceOnly")
                    //                    }
                    //
                    //                    dsDivider()
                    
                    dsPickerRow(title: "Language", value: selectedLanguage == "en-US" ? "English (US)" : selectedLanguage, options: ["English (US)"]) { _ in }
                    
                    dsDivider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hotkey")
                                .font(.system(size: 13.5))
                                .foregroundStyle(.white)
                            Text("Hold to record, release to transcribe. Click to change.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            HotkeyRecorderView(binding: $hotkey)
                                .fixedSize()
                                .onChange(of: hotkey) { _, newValue in
                                    TranscriptionSettings.hotkeyBinding = newValue
                                }
                            if hotkey != .fn {
                                Button {
                                    hotkey = .fn
                                    TranscriptionSettings.hotkeyBinding = .fn
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.white.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .help("Reset to Fn")
                            }
                        }
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
                }
                .onDisappear {
                    permissionManager.stopPollingAccessibility()
                }

                dsSectionHeader(icon: "sparkles", title: "Getting Started")

                dsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Replay setup")
                                .font(.system(size: 13.5))
                                .foregroundStyle(.white)
                            Text("Walk through the welcome, permissions, and try-it steps again.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                        Spacer()
                        dsCardButton(icon: "arrow.counterclockwise", label: "Replay") {
                            TranscriptionSettings.hasCompletedOnboarding = false
                            TranscriptionSettings.lastOnboardingStep = 0
                            appState.onShowOnboarding?()
                        }
                    }
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
