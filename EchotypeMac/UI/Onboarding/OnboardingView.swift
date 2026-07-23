//
//  OnboardingView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  First-run onboarding: Welcome → Permissions → Engine → Try it. Skippable and
//  resumable (the last reached step is persisted). Each permission is primed with
//  our own explanation before the real macOS prompt; denials fall back to a
//  System Settings deep-link. The user can't reach "Try it" until the three
//  permissions are green (but may skip). Completing sets hasCompletedOnboarding.
//

import SwiftUI
import AppKit

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, engine, tryIt
}

struct OnboardingView: View {
    @Environment(PermissionManager.self) var permissions
    @EnvironmentObject var appState: AppState
    /// Called when onboarding finishes or is skipped.
    var onDone: (() -> Void)?

    @State private var step: OnboardingStep = OnboardingStep(rawValue: TranscriptionSettings.lastOnboardingStep) ?? .welcome
    // Engine choice (mirrors settings; committed on advancing past step 3).
    @State private var useOpenAI = TranscriptionSettings.provider == .gptRealtime
    @State private var apiKey = TranscriptionSettings.openAIApiKey ?? ""
    // Hotkey for the "no Fn key" fallback in step 4.
    @State private var hotkey: HotkeyBinding = TranscriptionSettings.hotkeyBinding
    @State private var tryItSucceeded = TranscriptionSettings.firstDictationDone

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots + skip.
            header

            Group {
                switch step {
                case .welcome: welcomeStep
                case .permissions: permissionsStep
                case .engine: engineStep
                case .tryIt: tryItStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
        }
        .frame(width: 520, height: 560)
        .background(.ultraThickMaterial)   // match the main app's translucent look
        .onAppear {
            permissions.checkAll()
            permissions.startPollingAccessibility()
        }
        .onDisappear { permissions.stopPollingAccessibility() }
        .onChange(of: step) { _, newValue in
            TranscriptionSettings.lastOnboardingStep = newValue.rawValue
        }
        // Detect a successful dictation during the try-it step.
        .onChange(of: appState.phase) { _, _ in
            if TranscriptionSettings.firstDictationDone { tryItSucceeded = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.white.opacity(0.15))
                        .frame(width: s == step ? 22 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: step)
                }
            }
            Spacer()
            if step != .tryIt {
                Button("Skip setup") { finish(skip: true) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.white, Color.accentColor)
            Text("Dictate anywhere on your Mac.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                Text("Hold a key, speak, release. Echotype types it into whatever app you're in. Free and open source.")
                Text("Transcribe on-device for free, or connect your own OpenAI key for speed.")
            }
            .font(.system(size: 14))
            .foregroundStyle(Color.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            primaryButton("Get started") { advance() }
            Spacer().frame(height: 8)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("A few permissions", "Echotype needs these to hear you and type for you. You'll see a macOS prompt for each.")

            permissionRow(
                icon: "mic.fill",
                title: "Microphone",
                reason: "So Echotype can hear you when you dictate.",
                granted: permissions.microphoneGranted,
                denied: permissions.microphoneDenied,
                grant: { permissions.requestMicrophone() },
                openSettings: { permissions.openMicrophoneSettings() }
            )
            permissionRow(
                icon: "waveform",
                title: "Speech Recognition",
                reason: "To turn your speech into text on-device.",
                granted: permissions.speechRecognitionGranted,
                denied: permissions.speechRecognitionDenied,
                grant: { permissions.requestSpeechRecognition() },
                openSettings: { permissions.openSpeechRecognitionSettings() }
            )
            permissionRow(
                icon: "accessibility",
                title: "Accessibility",
                reason: "So Echotype can type the text into other apps for you.",
                granted: permissions.accessibilityGranted,
                denied: false,
                grant: { permissions.requestAccessibility() },
                openSettings: { permissions.requestAccessibility() }
            )

            Spacer()

            HStack(spacing: 12) {
                Button("Skip for now") { advance() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.5))
                Spacer()
                primaryButton(permissions.allPermissionsGranted ? "Continue" : "Grant permissions",
                              enabled: true) {
                    if permissions.allPermissionsGranted {
                        advance()
                    } else {
                        grantNextMissing()
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    /// Trigger the real prompt for the first not-yet-granted permission, in order.
    private func grantNextMissing() {
        if !permissions.microphoneGranted { permissions.requestMicrophone() }
        else if !permissions.speechRecognitionGranted { permissions.requestSpeechRecognition() }
        else if !permissions.accessibilityGranted { permissions.requestAccessibility() }
    }

    // MARK: - Step 3: Engine

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("Choose your engine", "You can switch this anytime in Settings.")

            engineCard(
                selected: !useOpenAI,
                title: "Built-in (macOS)",
                subtitle: "Free, on-device, private. No setup.",
                icon: "cpu"
            ) { useOpenAI = false }

            engineCard(
                selected: useOpenAI,
                title: "GPT Realtime (OpenAI)",
                subtitle: "Faster and more accurate. Needs your own API key.",
                icon: "bolt.fill"
            ) { useOpenAI = true }

            if useOpenAI {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField("sk-…", text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12), lineWidth: 1)))
                    Text("Stored securely in your Keychain. Leave blank to stay on the built-in engine.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }

            Spacer()
            primaryButton("Continue") { commitEngineAndAdvance() }
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private func commitEngineAndAdvance() {
        // If they chose OpenAI but left the key blank, keep them on Built-in
        // rather than shipping a broken state.
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if useOpenAI && !trimmedKey.isEmpty {
            TranscriptionSettings.openAIApiKey = trimmedKey
            TranscriptionSettings.provider = .gptRealtime
        } else {
            TranscriptionSettings.provider = .native
        }
        advance()
    }

    // MARK: - Step 4: Try it

    private var tryItStep: some View {
        VStack(spacing: 16) {
            Spacer()
            if tryItSucceeded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white, .green)
                Text("That's it — you're set up.")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                ZStack {
                    Circle().fill(appState.phase == .listening ? Color.green.opacity(0.25) : Color.white.opacity(0.06))
                        .frame(width: 90, height: 90)
                    Image(systemName: appState.phase == .listening ? "waveform" : "mic.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(appState.phase == .listening ? .green : Color.white.opacity(0.7))
                }
                Text("Try it")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    Text("Hold")
                    keycap(hotkey.displayName)
                    Text("and say anything.")
                }
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.75))
            }

            // No-Fn-key fallback: let them set an alternative hotkey right here.
            if !tryItSucceeded {
                VStack(spacing: 6) {
                    Text("No Globe/Fn key on your keyboard?")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                    HotkeyRecorderView(binding: $hotkey)
                        .fixedSize()
                        .onChange(of: hotkey) { _, newValue in
                            TranscriptionSettings.hotkeyBinding = newValue
                        }
                }
                .padding(.top, 4)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                tip("Fn + Space for hands-free mode.")
                tip("Add Snippets in the app to expand phrases.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            primaryButton("Done") { finish(skip: false) }
            Spacer().frame(height: 4)
        }
        .padding(.bottom, 24)
    }

    private func tip(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 10))
            Text("Tip: \(text)").font(.system(size: 11.5))
        }
        .foregroundStyle(Color.white.opacity(0.5))
    }

    // MARK: - Navigation

    private func advance() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.2)) { step = next }
        } else {
            finish(skip: false)
        }
    }

    private func finish(skip: Bool) {
        TranscriptionSettings.hasCompletedOnboarding = true
        TranscriptionSettings.lastOnboardingStep = 0
        onDone?()
    }

    // MARK: - Reusable pieces

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(icon: String, title: String, reason: String,
                               granted: Bool, denied: Bool,
                               grant: @escaping () -> Void,
                               openSettings: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.10)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white)
                Text(reason).font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            } else if denied {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.bordered).controlSize(.small).tint(.orange)
            } else {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5).frame(width: 16, height: 16)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
    }

    private func engineCard(selected: Bool, title: String, subtitle: String, icon: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Color.accentColor : Color.white.opacity(0.6))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Color.accentColor : Color.white.opacity(0.3))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(enabled ? Color.accentColor : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.18), lineWidth: 1)))
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .environment(PermissionManager())
        .environmentObject(AppState())
}
