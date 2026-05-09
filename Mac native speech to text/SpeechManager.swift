//
//  SpeechManager.swift
//  Mac native speech to text
//
//  Selects the active TranscriptionProvider and hands out fresh sessions.
//  Provider choice is read from UserDefaults each time a session is
//  created so toggling the model in Settings takes effect on the very
//  next recording without a restart.
//

import Foundation

final class SpeechManager: @unchecked Sendable {
    static let providerDefaultsKey = "setting_transcriptionProviderID"
    static let providerChangedNotification = Notification.Name("SpeechManagerProviderChanged")

    private let appleProvider = AppleSpeechProvider()
    private var moonshineProvider: MoonshineProvider?

    /// Returns the user's currently selected provider, falling back to
    /// Apple Native if the chosen provider isn't ready (e.g. Moonshine
    /// model isn't installed yet).
    func activeProvider() -> TranscriptionProvider {
        let raw = UserDefaults.standard.string(forKey: Self.providerDefaultsKey)
        let selected = raw.flatMap(TranscriptionProviderID.init(rawValue:)) ?? .appleNative

        switch selected {
        case .appleNative:
            return appleProvider
        case .moonshineTiny:
            if let model = ModelRegistry.model(for: .moonshineTiny), model.isInstalled() {
                if moonshineProvider == nil {
                    moonshineProvider = MoonshineProvider(modelInfo: model)
                }
                if let provider = moonshineProvider, provider.isReady {
                    return provider
                }
            }
            return appleProvider
        }
    }

    func createSession(onResult: @escaping (String, Bool) -> Void,
                       audioLevelMonitor: AudioLevelMonitor? = nil) -> TranscriptionSession? {
        return activeProvider().makeSession(onResult: onResult, audioLevelMonitor: audioLevelMonitor)
    }

    /// Drop any cached Moonshine runtime — call after the user installs or
    /// uninstalls the model so the next session reloads the new state.
    func reset() {
        moonshineProvider = nil
    }
}
