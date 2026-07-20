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
    /// Transcript succeeded and was pasted, but the grammar/rephrase pass failed.
    /// The overlay shows the reason + a Retry that re-runs cleanup.
    case cleanupFailed
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

    /// Human-readable reason shown when the cleanup (grammar/rephrase) pass failed
    /// after the raw transcript was already pasted. Drives the `.cleanupFailed` UI.
    @Published var cleanupFailureReason: String?
    /// True when the cleanup failure was specifically out-of-credits, so the
    /// overlay can nudge the user to top up rather than just "retry".
    @Published var cleanupOutOfCredits = false
    /// The raw transcript to re-run cleanup on when the user taps Retry.
    private var cleanupRetryText: String?
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
    /// Identifies the in-flight processing session so a stale fallback timer
    /// can't act on a session that already resolved (or was replaced).
    private var processingToken: UUID?

    /// Ensure text ends with sentence-ending punctuation and a trailing space.
    private func finalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return trimmed }
        // Multi-line output (a formatted list or multiple paragraphs) shouldn't
        // get a period glued onto the last line — just ensure a trailing space.
        if trimmed.contains("\n") {
            return trimmed + " "
        }
        let lastChar = trimmed.last!
        if [".", "!", "?", "…"].contains(String(lastChar)) {
            return trimmed + " "
        }
        return trimmed + ". "
    }

    /// Run optional LLM cleanup (grammar/rephrase/list formatting), then
    /// post-processing + snippets, and insert the final text at the cursor.
    ///
    /// The overlay stays in `.processing` (spinner) while cleanup runs, so the
    /// user never sees a gap where "nothing happened". Outcomes:
    ///   • skipped/cleaned → insert, hide overlay
    ///   • failed → insert the RAW text anyway, then show `.cleanupFailed` with a
    ///     reason + Retry (per the user's request — text is never lost).
    private func applyAndInsert(_ text: String, recordingDuration: Double?) {
        // If cleanup will actually run, make sure the spinner is showing.
        if TranscriptionSettings.cleanupEnabled, phase != .processing {
            phase = .processing
        }

        TextCleanup.clean(text) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .skipped(let t), .cleaned(let t):
                self.insertProcessed(t, recordingDuration: recordingDuration)
                self.cleanupFailureReason = nil
                self.cleanupOutOfCredits = false
                self.phase = .hidden
                self.onHide?()

            case .failed(let original, let reason, let outOfCredits):
                // Paste the raw transcript so nothing is lost…
                self.insertProcessed(original, recordingDuration: recordingDuration)
                // …then surface the cleanup failure with a Retry.
                self.cleanupRetryText = original
                self.cleanupFailureReason = reason
                self.cleanupOutOfCredits = outOfCredits
                AppLog.shared.log("AppState", "cleanup failed: \(reason) — pasted raw, showing retry")
                self.phase = .cleanupFailed
            }
        }
    }

    /// Post-process + snippets + finalize, then insert at the cursor.
    private func insertProcessed(_ text: String, recordingDuration: Double?) {
        let postProcessed = PostProcessor.process(text)
        let processed = finalize(snippetManager?.applySnippets(to: postProcessed) ?? postProcessed)
        if let duration = recordingDuration {
            usageTracker?.recordSession(text: processed, recordingDuration: duration)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            TextInserter.insert(processed)
            AppLog.shared.log("AppState", "inserted (\(processed.count) chars)")
        }
    }

    /// Retry the grammar/rephrase pass after it failed. On success the cleaned
    /// text is pasted at the current cursor (after the raw text already there).
    func retryCleanup() {
        guard let raw = cleanupRetryText else {
            phase = .hidden; onHide?(); return
        }
        phase = .processing
        TextCleanup.clean(raw) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .cleaned(let t):
                self.insertProcessed(t, recordingDuration: nil)
                self.cleanupRetryText = nil
                self.cleanupFailureReason = nil
                self.cleanupOutOfCredits = false
                self.phase = .hidden
                self.onHide?()
            case .skipped:
                // Toggles were turned off in the meantime — nothing to do.
                self.cleanupRetryText = nil
                self.phase = .hidden
                self.onHide?()
            case .failed(_, let reason, let outOfCredits):
                self.cleanupFailureReason = reason
                self.cleanupOutOfCredits = outOfCredits
                AppLog.shared.log("AppState", "cleanup retry failed: \(reason)")
                self.phase = .cleanupFailed
            }
        }
    }

    /// Dismiss the cleanup-failed overlay without retrying (raw text stays).
    func dismissCleanupFailure() {
        cleanupRetryText = nil
        cleanupFailureReason = nil
        cleanupOutOfCredits = false
        phase = .hidden
        onHide?()
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
                    AppLog.shared.log("AppState", "final: \"\(text)\"")
                    self.processingToken = nil
                    VolumeManager.shared.restoreSystem()
                    if text.isEmpty {
                        self.phase = .hidden
                        self.onHide?()
                    } else {
                        // Keep the overlay spinner up through cleanup so it never
                        // looks like nothing happened. applyAndInsert drives the
                        // final hide / cleanup-failed state itself.
                        self.applyAndInsert(text, recordingDuration: CFAbsoluteTimeGetCurrent() - self.recordingStartTime)
                    }
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
        AppLog.shared.log("AppState", "=== STOP → PROCESSING ===")
        phase = .processing
        audioLevelMonitor.reset()

        // Track this specific session so a stale fallback from a previous
        // capture can't clobber a newer one.
        let token = UUID()
        processingToken = token

        // Global fallback: the session (GPT path uploads via REST, which has its
        // own 180s timeout + retries; native resolves quickly) is expected to
        // always call back. This only recovers if it truly hangs, so keep it
        // generous — a short fallback used to hide the overlay mid-upload on long
        // audio, dropping the result.
        let recordedDuration = CFAbsoluteTimeGetCurrent() - recordingStartTime
        let fallback = max(200.0, recordedDuration + 60.0)

        session.stopAndTranscribe()

        DispatchQueue.main.asyncAfter(deadline: .now() + fallback) { [weak self] in
            guard let self = self, self.phase == .processing, self.processingToken == token else { return }
            AppLog.shared.log("AppState", "fallback fired after \(Int(fallback))s — session never resolved")
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
        AppLog.shared.log("AppState", "=== FAILED: \(reason) ===")
        VolumeManager.shared.restoreSystem()
        processingToken = nil
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
