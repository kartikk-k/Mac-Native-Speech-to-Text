//
//  TranscriptionProvider.swift
//  Mac native speech to text
//
//  Abstraction over different speech-to-text backends. Today we support
//  Apple's on-device SFSpeechRecognizer and a downloadable Moonshine Tiny
//  ONNX model. The protocol is designed so additional providers (other
//  open-source models, cloud APIs, etc.) can be slotted in later.
//

import Foundation
import AVFoundation

/// Identifier for a transcription backend. Stored in UserDefaults so the
/// user's choice persists across launches.
enum TranscriptionProviderID: String, CaseIterable, Identifiable, Codable {
    case appleNative = "apple_native"
    case moonshineTiny = "moonshine_tiny"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleNative: return "Apple Native"
        case .moonshineTiny: return "Moonshine Tiny"
        }
    }
}

/// Result delivered from a session. `isFinal == true` means no further
/// callbacks will fire for this session.
struct TranscriptionUpdate {
    let text: String
    let isFinal: Bool
}

/// Errors a provider may surface while preparing or transcribing.
enum TranscriptionProviderError: Error, LocalizedError {
    case providerUnavailable(String)
    case modelNotInstalled
    case audioFormatUnsupported
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let why):
            return "Provider unavailable: \(why)"
        case .modelNotInstalled:
            return "The selected model is not installed. Open Settings to download it."
        case .audioFormatUnsupported:
            return "The current audio format is not supported by the selected model."
        case .inferenceFailed(let why):
            return "Inference failed: \(why)"
        }
    }
}

/// One in-progress recording+transcription. Each recording uses a fresh
/// session so multiple invocations cannot interfere.
protocol TranscriptionSession: AnyObject {
    var isRecording: Bool { get }

    func startRecording()
    func stopAndTranscribe()
    func cancel()
}

/// Factory for sessions. A provider is a long-lived object created once and
/// asked for fresh sessions on demand.
protocol TranscriptionProvider: AnyObject {
    var id: TranscriptionProviderID { get }

    /// Whether the provider is ready to handle a new session right now. For
    /// example a model-based provider returns false until the model is on
    /// disk and loaded.
    var isReady: Bool { get }

    func makeSession(
        onResult: @escaping (String, Bool) -> Void,
        audioLevelMonitor: AudioLevelMonitor?
    ) -> TranscriptionSession?
}
