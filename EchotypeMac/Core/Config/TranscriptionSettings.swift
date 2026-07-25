//
//  TranscriptionSettings.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Foundation
import Security

/// Which engine converts speech to text.
enum TranscriptionProvider: String, CaseIterable {
    /// Apple's built-in on-device speech recognition (default).
    case native
    /// OpenAI's Realtime transcription (gpt-4o-transcribe), streamed over a WebSocket.
    case gptRealtime

    var displayName: String {
        switch self {
        case .native: return "Built-in (macOS)"
        case .gptRealtime: return "GPT Realtime (OpenAI)"
        }
    }
}

/// Central store for transcription-engine preferences.
/// Provider + model live in UserDefaults; the API key lives in the Keychain.
enum TranscriptionSettings {
    private static let providerKey = "setting_transcriptionProvider"
    private static let modelKey = "setting_gptRealtimeModel"
    private static let grammarKey = "setting_fixGrammar"
    private static let rephraseKey = "setting_rephrase"

    /// Model used for the post-transcription cleanup pass (grammar/rephrase/list
    /// formatting). Cheap and fast; only invoked when a cleanup toggle is on.
    static let cleanupModel = "gpt-4o-mini"

    /// Fix grammar while inserting (default OFF). Runs a quick LLM cleanup pass
    /// that corrects grammar and formats lists, preserving the user's meaning.
    static var fixGrammar: Bool {
        get { UserDefaults.standard.object(forKey: grammarKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: grammarKey) }
    }

    /// Rephrase for clarity while inserting (default OFF). When on, the cleanup
    /// pass also polishes phrasing and flow (clean & polish, meaning preserved).
    static var rephrase: Bool {
        get { UserDefaults.standard.object(forKey: rephraseKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: rephraseKey) }
    }

    /// Optional user instructions appended to the grammar-fix system prompt when
    /// Fix grammar is on. E.g. "keep my casual tone", "use British spelling".
    private static let grammarInstructionsKey = "setting_grammarInstructions"
    static var grammarInstructions: String {
        get { UserDefaults.standard.string(forKey: grammarInstructionsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: grammarInstructionsKey) }
    }

    /// Optional user instructions appended to the rephrase system prompt when
    /// Rephrase is on. E.g. "make it more concise", "professional tone".
    private static let rephraseInstructionsKey = "setting_rephraseInstructions"
    static var rephraseInstructions: String {
        get { UserDefaults.standard.string(forKey: rephraseInstructionsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: rephraseInstructionsKey) }
    }

    /// Show the menu bar icon (default ON). Users who prefer a hotkey-only,
    /// icon-free experience can turn it off in Settings.
    private static let showMenuBarKey = "setting_showMenuBarIcon"
    static var showMenuBarIcon: Bool {
        get { UserDefaults.standard.object(forKey: showMenuBarKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showMenuBarKey) }
    }

    /// The hold-to-record hotkey. Defaults to Fn (Globe). Changing it posts
    /// `.hotkeyBindingChanged` so HotkeyMonitor can reload live.
    static let hotkeyBindingChanged = Notification.Name("EchotypeHotkeyBindingChanged")
    private static let hotkeyKey = "setting_hotkeyBinding"
    static var hotkeyBinding: HotkeyBinding {
        get {
            if let raw = UserDefaults.standard.string(forKey: hotkeyKey),
               let b = HotkeyBinding(storage: raw) { return b }
            return .fn
        }
        set {
            UserDefaults.standard.set(newValue.storageString, forKey: hotkeyKey)
            NotificationCenter.default.post(name: hotkeyBindingChanged, object: nil)
        }
    }

    /// True when any cleanup toggle is on AND an OpenAI key is present (the pass
    /// needs the API). If no key, cleanup is silently skipped.
    static var cleanupEnabled: Bool {
        (fixGrammar || rephrase) && hasOpenAIKey
    }

    // MARK: - Onboarding

    private static let onboardingDoneKey = "setting_hasCompletedOnboarding"
    private static let firstDictationKey = "setting_firstDictationDone"
    private static let onboardingStepKey = "setting_lastOnboardingStep"

    /// True once the user has finished (or skipped) first-run onboarding.
    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingDoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingDoneKey) }
    }

    /// True once the user has completed at least one successful dictation. Lets
    /// Home adapt (e.g. collapse the how-to) and the onboarding "try it" step
    /// know it succeeded.
    static var firstDictationDone: Bool {
        get { UserDefaults.standard.bool(forKey: firstDictationKey) }
        set { UserDefaults.standard.set(newValue, forKey: firstDictationKey) }
    }

    /// Last onboarding step index reached, so an interrupted run resumes there.
    static var lastOnboardingStep: Int {
        get { UserDefaults.standard.integer(forKey: onboardingStepKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingStepKey) }
    }

    private static let keychainService = "com.peakhumanexperience.echotype.openai"
    private static let keychainAccount = "openai-api-key"

    /// Default OpenAI Realtime transcription model.
    static let defaultModel = "gpt-realtime-whisper"

    /// Model used for the live realtime (WebSocket) transcription session. This
    /// is always the streaming Whisper model — it's the only one that works over
    /// the realtime transcription session and gives progressive deltas.
    static let realtimeModel = "gpt-realtime-whisper"

    /// Model used for retry-from-failed-list (REST /v1/audio/transcriptions).
    /// gpt-realtime-whisper is WebSocket-only, so the REST retry path uses a
    /// REST-capable transcription model instead.
    static let restRetryModel = "gpt-4o-transcribe"

    static var provider: TranscriptionProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: providerKey) ?? TranscriptionProvider.native.rawValue
            return TranscriptionProvider(rawValue: raw) ?? .native
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    static var model: String {
        get {
            let stored = UserDefaults.standard.string(forKey: modelKey) ?? ""
            return stored.isEmpty ? defaultModel : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    /// The OpenAI API key. Stored in the app config (UserDefaults) — intentionally
    /// NOT the Keychain, to avoid the "wants to use your confidential information"
    /// password prompt. (One-time migration reads any pre-existing Keychain value.)
    private static let apiKeyDefaultsKey = "setting_openAIApiKey"
    static var openAIApiKey: String? {
        get {
            if let stored = UserDefaults.standard.string(forKey: apiKeyDefaultsKey), !stored.isEmpty {
                return stored
            }
            // Migrate a legacy Keychain value once, then stop touching the Keychain.
            if let legacy = KeychainHelper.read(service: keychainService, account: keychainAccount),
               !legacy.isEmpty {
                UserDefaults.standard.set(legacy, forKey: apiKeyDefaultsKey)
                KeychainHelper.delete(service: keychainService, account: keychainAccount)
                return legacy
            }
            return nil
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: apiKeyDefaultsKey)
            }
        }
    }

    static var hasOpenAIKey: Bool {
        !(openAIApiKey ?? "").isEmpty
    }

    /// True when GPT Realtime is selected AND a key is present. If a key is
    /// missing we transparently fall back to the built-in engine.
    static var usesGPTRealtime: Bool {
        provider == .gptRealtime && hasOpenAIKey
    }
}

/// Minimal Keychain wrapper for a single string secret.
enum KeychainHelper {
    static func save(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
