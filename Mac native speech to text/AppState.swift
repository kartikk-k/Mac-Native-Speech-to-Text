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
    case failed
}

/// Tracks how the last session ended — used by Learn tab to detect user actions.
enum SessionEndReason {
    case none
    case released       // normal hold-and-release
    case handsFreeStop  // ended hands-free via Space/Escape/Fn+Space
    case cancelled      // deleted/cancelled recording
}

class AppState: ObservableObject {
    @Published var phase: RecognitionPhase = .hidden
    @Published var transcribedText = ""
    @Published var isHandsFree = false
    @Published var lastEndReason: SessionEndReason = .none

    /// The most recent failed capture awaiting retry (drives the overlay retry UI).
    @Published var lastFailed: FailedTranscription?
    /// Set to request the main window navigate to a specific tab.
    @Published var requestedTab: MainTab?
    /// Set so the Retry tab can scroll to / highlight a specific failed item.
    @Published var pendingFailedFocusID: UUID?

    let audioLevelMonitor = AudioLevelMonitor()
    private let speechManager = SpeechManager()
    private var currentSession: TranscriptionSession?

    var onHide: (() -> Void)?
    var onShowOnboarding: (() -> Void)?
    var onShowMainWindow: (() -> Void)?
    var permissionManager: PermissionManager?
    var usageTracker: UsageTracker?
    var snippetManager: SnippetManager?
    var failedStore: FailedTranscriptionStore?

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

    /// Run post-processing + snippets and insert the final text at the cursor.
    private func applyAndInsert(_ text: String, recordingDuration: Double?) {
        let postProcessed = PostProcessor.process(text)
        let processed = finalize(snippetManager?.applySnippets(to: postProcessed) ?? postProcessed)
        if let duration = recordingDuration {
            usageTracker?.recordSession(text: processed, recordingDuration: duration)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            TextInserter.insert(processed)
            print("[AppState] inserted")
        }
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
                        self.applyAndInsert(text, recordingDuration: CFAbsoluteTimeGetCurrent() - self.recordingStartTime)
                    }
                    VolumeManager.shared.restoreSystem()
                    self.phase = .hidden
                    self.onHide?()
                }
            }
        }, onFailure: { [weak self] audioURL, reason in
            DispatchQueue.main.async {
                self?.handleFailure(audioURL: audioURL, reason: reason)
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
                self.applyAndInsert(text, recordingDuration: nil)
            }
            VolumeManager.shared.restoreSystem()
            self.phase = .hidden
            self.onHide?()
        }
    }

    func cancelListening() {
        print("[AppState] === CANCEL ===")
        lastEndReason = .cancelled
        currentSession?.cancel()
        currentSession = nil
        audioLevelMonitor.reset()
        VolumeManager.shared.restoreSystem()
        phase = .hidden
        transcribedText = ""
        onHide?()
    }

    // MARK: - Failure & Retry

    /// A capture couldn't be transcribed. Save the audio and surface retry UI.
    private func handleFailure(audioURL: URL, reason: String) {
        print("[AppState] === FAILED: \(reason) ===")
        VolumeManager.shared.restoreSystem()
        currentSession = nil

        let saved = failedStore?.add(
            sourceURL: audioURL,
            provider: .gptRealtime,
            model: TranscriptionSettings.model,
            error: reason
        )
        lastFailed = saved
        transcribedText = ""

        if saved != nil {
            // Keep the overlay up, showing retry / open options.
            phase = .failed
        } else {
            phase = .hidden
            onHide?()
        }
    }

    /// Retry the most recent failure directly from the overlay. On success the
    /// text is inserted at the cursor, just like a normal capture.
    func retryLastFailed() {
        guard let item = lastFailed, let store = failedStore else { return }
        phase = .processing
        retry(item: item, store: store, insertOnSuccess: true) { [weak self] success, _ in
            guard let self = self else { return }
            if success {
                self.lastFailed = nil
                self.phase = .hidden
                self.onHide?()
            } else {
                // Stay in the failed state so the user can try again / open the app.
                self.phase = .failed
            }
        }
    }

    /// Shared retry used by the overlay and the Retry tab.
    /// - Parameter insertOnSuccess: insert the text at the cursor (overlay flow).
    ///   When false, the text is returned via `completion` so the caller can
    ///   copy or display it (in-app flow, where our own window has focus).
    /// - Parameter completion: `(succeeded, transcribedText)` on the main queue.
    func retry(item: FailedTranscription,
               store: FailedTranscriptionStore,
               insertOnSuccess: Bool,
               completion: @escaping (Bool, String?) -> Void) {
        let provider = TranscriptionProvider(rawValue: item.provider) ?? .native
        let url = store.audioURL(for: item)
        FileTranscriber.transcribe(url: url, provider: provider, model: item.model) { result in
            switch result {
            case .success(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if insertOnSuccess && !trimmed.isEmpty {
                    self.applyAndInsert(trimmed, recordingDuration: nil)
                }
                store.remove(item)
                completion(true, trimmed)
            case .failure(let error):
                print("[AppState] retry failed: \(error.message)")
                completion(false, nil)
            }
        }
    }

    /// Open the main app focused on the failed capture so the user can retry manually.
    func openFailedInApp() {
        pendingFailedFocusID = lastFailed?.id
        requestedTab = .retry
        onShowMainWindow?()
        phase = .hidden
        onHide?()
    }
}
