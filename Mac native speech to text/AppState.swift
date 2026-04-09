//
//  AppState.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Foundation
import Combine
import AppKit

enum RecognitionPhase {
    case hidden
    case listening
    case processing
    case permissionDenied
}

class AppState: ObservableObject {
    @Published var phase: RecognitionPhase = .hidden
    @Published var transcribedText = ""

    let audioLevelMonitor = AudioLevelMonitor()
    private let speechManager = SpeechManager()
    private var currentSession: SpeechSession?

    var onHide: (() -> Void)?
    var onShowOnboarding: (() -> Void)?
    var onShowMainWindow: (() -> Void)?
    var permissionManager: PermissionManager?
    var usageTracker: UsageTracker?
    var snippetManager: SnippetManager?

    private var recordingStartTime: CFAbsoluteTime = 0

    /// Ensure text ends with sentence-ending punctuation and a trailing space.
    private func finalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return trimmed }
        let lastChar = trimmed.last!
        if [".", "!", "?", "…"].contains(String(lastChar)) {
            return trimmed + " "
        }
        return trimmed + ". "
    }

    func startListening() {
        if let pm = permissionManager, !pm.allPermissionsGranted {
            phase = .permissionDenied
            return
        }

        if let old = currentSession {
            if old.isRecording { old.cancel() }
        }

        print("[AppState] === START ===")
        phase = .listening
        transcribedText = ""
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        VolumeManager.shared.muteSystem()
        audioLevelMonitor.reset()

        let session = speechManager.createSession(onResult: { [weak self] text, isFinal in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if !isFinal {
                    if self.phase == .processing {
                        self.transcribedText = text
                    }
                } else {
                    print("[AppState] final: \"\(text)\"")
                    if !text.isEmpty {
                        let processed = self.finalize(self.snippetManager?.applySnippets(to: text) ?? text)
                        let duration = CFAbsoluteTimeGetCurrent() - self.recordingStartTime
                        self.usageTracker?.recordSession(text: processed, recordingDuration: duration)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            TextInserter.insert(processed)
                            print("[AppState] inserted")
                        }
                    }
                    VolumeManager.shared.restoreSystem()
                    self.phase = .hidden
                    self.onHide?()
                }
            }
        }, audioLevelMonitor: audioLevelMonitor)

        guard let session = session else {
            phase = .hidden
            return
        }

        currentSession = session
        session.startRecording()
    }

    func stopListening() {
        guard phase == .listening, let session = currentSession else { return }
        print("[AppState] === STOP → PROCESSING ===")
        phase = .processing
        audioLevelMonitor.reset()
        session.stopAndTranscribe()

        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self, self.phase == .processing else { return }
            let text = self.transcribedText
            if !text.isEmpty {
                let processed = self.finalize(self.snippetManager?.applySnippets(to: text) ?? text)
                TextInserter.insert(processed)
            }
            VolumeManager.shared.restoreSystem()
            self.phase = .hidden
            self.onHide?()
        }
    }

    func cancelListening() {
        print("[AppState] === CANCEL ===")
        currentSession?.cancel()
        currentSession = nil
        audioLevelMonitor.reset()
        VolumeManager.shared.restoreSystem()
        phase = .hidden
        transcribedText = ""
        onHide?()
    }
}
