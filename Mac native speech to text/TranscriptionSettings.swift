//
//  TranscriptionSettings.swift
//  Mac native speech to text
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

    private static let keychainService = "com.peakhumanexperience.echotype.openai"
    private static let keychainAccount = "openai-api-key"

    /// Default OpenAI Realtime transcription model.
    static let defaultModel = "gpt-4o-transcribe"

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

    /// The OpenAI API key, stored securely in the Keychain.
    static var openAIApiKey: String? {
        get { KeychainHelper.read(service: keychainService, account: keychainAccount) }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                KeychainHelper.delete(service: keychainService, account: keychainAccount)
            } else {
                KeychainHelper.save(trimmed, service: keychainService, account: keychainAccount)
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
