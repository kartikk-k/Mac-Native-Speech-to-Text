//
//  AppState.swift
//  Echotype Mac
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
    /// The transcript is done; the grammar/rephrase pass (2nd API call) is
    /// running. Shown with its own spinner so it never looks like "nothing
    /// happened" while text is being improved.
    case cleaning
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

    let audioLevelMonitor = AudioLevelMonitor()
    private let speechManager = SpeechManager()
    private var currentSession: TranscriptionSession?

    var onHide: (() -> Void)?
    /// Re-show the recording overlay (used to guarantee the spinner is visible
    /// during the cleanup pass, in case the overlay was dismissed).
    var onShow: (() -> Void)?
    var onShowOnboarding: (() -> Void)?
    var onShowMainWindow: (() -> Void)?
    var permissionManager: PermissionManager?
    var usageTracker: UsageTracker?
    var snippetManager: SnippetManager?
    var failedStore: FailedTranscriptionStore?
    var historyStore: HistoryStore?

    private var recordingStartTime: CFAbsoluteTime = 0
    /// Audio file for the in-flight capture (fed to history on success).
    private var pendingAudioURL: URL?
    /// Incremented on every startListening. A session's callbacks capture the
    /// generation they were created in and are IGNORED if a newer session has
    /// since started — otherwise a dead/failed session firing late would clobber
    /// the current one's phase and leave the overlay stuck "loading".
    private var sessionGeneration = 0
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
        // If the grammar/rephrase pass will run, show a dedicated "cleaning"
        // spinner so the overlay never looks empty while the 2nd API call runs.
        if TranscriptionSettings.cleanupEnabled {
            phase = .cleaning
            onShow?()
        }

        TextCleanup.clean(text) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .skipped(let t):
                self.insertProcessed(t, recordingDuration: recordingDuration)
                self.recordHistory(raw: text, cleaned: "", recordingDuration: recordingDuration)
                self.cleanupFailureReason = nil
                self.cleanupOutOfCredits = false
                self.phase = .hidden
                self.onHide?()

            case .cleaned(let t):
                self.insertProcessed(t, recordingDuration: recordingDuration)
                self.recordHistory(raw: text, cleaned: t, recordingDuration: recordingDuration)
                self.cleanupFailureReason = nil
                self.cleanupOutOfCredits = false
                self.phase = .hidden
                self.onHide?()

            case .failed(let original, let reason, let outOfCredits):
                // Paste the raw transcript so nothing is lost…
                self.insertProcessed(original, recordingDuration: recordingDuration)
                self.recordHistory(raw: text, cleaned: "", recordingDuration: recordingDuration)
                // …then surface the cleanup failure with a Retry.
                self.cleanupRetryText = original
                self.cleanupFailureReason = reason
                self.cleanupOutOfCredits = outOfCredits
                AppLog.shared.log("AppState", "cleanup failed: \(reason) — pasted raw, showing retry")
                self.phase = .cleanupFailed
            }
        }
    }

    /// Save this transcription to the local history (last 100). Consumes the
    /// pending audio file for this capture, if any.
    private func recordHistory(raw: String, cleaned: String, recordingDuration: Double?) {
        let audio = pendingAudioURL
        pendingAudioURL = nil
        historyStore?.add(
            rawText: raw,
            cleanedText: cleaned,
            grammarApplied: TranscriptionSettings.fixGrammar,
            rephraseApplied: TranscriptionSettings.rephrase,
            model: TranscriptionSettings.usesGPTRealtime ? TranscriptionSettings.realtimeModel : TranscriptionProvider.native.displayName,
            durationSeconds: recordingDuration ?? 0,
            audioSource: audio
        )
        // The audio was copied into history; clean up the temp file.
        if let audio = audio { try? FileManager.default.removeItem(at: audio) }
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

        // Fully tear down ANY previous session — recording or not. A session that
        // already stopped may still be waiting on a socket/timeout; if it fires
        // later it must not touch the new session's state.
        if let old = currentSession {
            old.cancel()
            currentSession = nil
        }
        // Invalidate every in-flight timeout/callback from the old generation.
        sessionGeneration += 1
        let generation = sessionGeneration
        processingToken = nil
        pendingAudioURL = nil

        AppLog.shared.log("AppState", "=== START (gen \(generation)) ===")
        phase = .listening
        transcribedText = ""
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        VolumeManager.shared.muteSystem()
        audioLevelMonitor.reset()

        // Ignore any callback from a session that's no longer the current one.
        func isCurrent() -> Bool { generation == sessionGeneration }

        let session = speechManager.createSession(onResult: { [weak self] text, isFinal in
            DispatchQueue.main.async {
                guard let self = self, isCurrent() else { return }

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
                guard let self = self, isCurrent() else { return }
                self.handleFailure(audioURL: audioURL, reason: reason)
            }
        }, onAudioSaved: { [weak self] audioURL in
            DispatchQueue.main.async {
                guard let self = self, isCurrent() else { return }
                self.pendingAudioURL = audioURL
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

        // Global fallback so the overlay can NEVER get stuck "loading" forever.
        // The streaming WebSocket resolves in seconds; the session also has its
        // own 8s final-transcript timeout. Scale gently with audio length but cap
        // it so a hang recovers fast instead of leaving the user staring at a
        // spinner (the old 200s value felt exactly like "keeps loading").
        let recordedDuration = CFAbsoluteTimeGetCurrent() - recordingStartTime
        let fallback = min(45.0, max(15.0, recordedDuration + 12.0))

        session.stopAndTranscribe()

        DispatchQueue.main.asyncAfter(deadline: .now() + fallback) { [weak self] in
            guard let self = self, self.phase == .processing, self.processingToken == token else { return }
            AppLog.shared.log("AppState", "fallback fired after \(Int(fallback))s — session never resolved")
            let text = self.transcribedText
            self.processingToken = nil
            if !text.isEmpty {
                self.applyAndInsert(text, recordingDuration: nil)
            } else {
                self.phase = .hidden
                self.onHide?()
            }
            VolumeManager.shared.restoreSystem()
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

        let duration = CFAbsoluteTimeGetCurrent() - recordingStartTime

        // Record the failure in History too, so everything lives in one place
        // (a failed entry keeps its audio + a Retry). Copy the audio for history
        // BEFORE the failedStore moves the original file.
        historyStore?.addFailed(
            reason: reason,
            provider: .gptRealtime,
            model: TranscriptionSettings.realtimeModel,
            durationSeconds: duration,
            audioSource: copyForHistory(audioURL)
        )

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

    /// Duplicate a temp audio file so both History and the failed store can own a
    /// copy (the failed store moves the original). Returns nil if it can't.
    private func copyForHistory(_ url: URL) -> URL? {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("echotype-histcopy-\(UUID().uuidString).wav")
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
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

    /// Retry a FAILED history entry: re-transcribe its saved audio over REST and,
    /// on success, fill the entry in place. Completion reports the fresh text (for
    /// clipboard) on the main queue.
    func retryHistory(_ entry: HistoryEntry, completion: @escaping (Bool, String?) -> Void) {
        guard let store = historyStore, let url = store.audioURL(for: entry) else {
            completion(false, nil); return
        }
        let provider = TranscriptionProvider(rawValue: entry.provider) ?? .gptRealtime
        FileTranscriber.transcribe(url: url, provider: provider, model: entry.model) { result in
            switch result {
            case .success(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                store.markTranscribed(entry.id, rawText: trimmed, cleanedText: "")
                completion(true, trimmed)
            case .failure:
                completion(false, nil)
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

    /// Open the app on the History page, where failed captures now live for retry.
    func openFailedInApp() {
        requestedTab = .history
        onShowMainWindow?()
        phase = .hidden
        onHide?()
    }
}
