//
//  GPTRealtimeSession.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Live streaming speech-to-text over OpenAI's Realtime transcription WebSocket
//  using gpt-realtime-whisper. Audio is streamed up as the user speaks, so the
//  transcript arrives progressively (fast, single output) and the socket never
//  sits idle (which previously caused 1006 "connection lost" closes).
//
//  Long audio: every ~60s while recording we commit the input buffer so the
//  server finalizes that segment and emits its transcript, then keep streaming
//  into the next segment. Finalized segments are stitched into one continuous
//  transcript — so recordings of any length work without hitting per-request
//  size/duration limits.
//
//  Every captured sample is also retained so that, if the session fails
//  (dropped connection, API error, timeout), we can persist the audio as a WAV
//  and hand it to the failed-capture store for retry — the audio is never lost.
//
//  Note: the global hotkey event tap runs on its own thread (HotkeyMonitor), so
//  nothing here can freeze system input.
//

import Foundation
import AVFoundation

final class GPTRealtimeSession: NSObject, TranscriptionSession, URLSessionWebSocketDelegate, @unchecked Sendable {
    let id = UUID()

    private let apiKey: String
    private let model: String
    private let onResult: (String, Bool) -> Void
    /// Called (on the main queue) when the capture couldn't be transcribed.
    /// Provides a WAV file of the recording and a human-readable reason.
    private let onFailure: (URL, String) -> Void
    /// Called (on the main queue) with the recorded WAV when a capture succeeds,
    /// so it can be kept in history.
    private let onAudioSaved: ((URL) -> Void)?
    private weak var audioLevelMonitor: AudioLevelMonitor?

    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let sampleRate = 24000
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 24000,
                                             channels: 1,
                                             interleaved: true)

    /// Commit the input buffer this often so long audio is transcribed in
    /// ~1-minute segments instead of one huge request.
    private let chunkInterval: CFTimeInterval = 60

    private var urlSession: URLSession?
    private var webSocket: URLSessionWebSocketTask?

    private let stateLock = NSLock()
    private var _isRecording = false
    private var isConnected = false
    private var awaitingFinal = false
    private var finished = false
    private var connectionFailed = false

    /// PCM captured before the socket opened, flushed on open.
    private var pendingAudio = Data()
    /// Raw 24 kHz mono PCM16 of the whole capture (for retry-on-failure WAV).
    private var recordedPCM = Data()
    private var loggedFirstBuffer = false

    /// Segments finalized by `.completed` events, joined for the final output.
    private var committedTranscript = ""
    /// Live delta text for the segment currently being transcribed.
    private var partialText = ""
    /// Whether we've committed at least once (so a final commit isn't a no-op).
    private var lastCommitTime: CFTimeInterval = 0

    private var recordingStartTime: CFAbsoluteTime = 0
    private var chunkTimer: DispatchSourceTimer?
    private var finalTimeout: DispatchWorkItem?

    private var tag: String { String(id.uuidString.prefix(4)) }
    private func log(_ msg: String) { AppLog.shared.log("GPT \(tag)", msg) }

    var isRecording: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _isRecording
    }

    init(apiKey: String,
         model: String,
         onResult: @escaping (String, Bool) -> Void,
         onFailure: @escaping (URL, String) -> Void,
         onAudioSaved: ((URL) -> Void)? = nil,
         audioLevelMonitor: AudioLevelMonitor? = nil) {
        self.apiKey = apiKey
        self.model = model
        self.onResult = onResult
        self.onFailure = onFailure
        self.onAudioSaved = onAudioSaved
        self.audioLevelMonitor = audioLevelMonitor
        super.init()
    }

    // MARK: - TranscriptionSession

    func startRecording() {
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        lastCommitTime = CFAbsoluteTimeGetCurrent()
        log("start recording (model: \(model))")

        stateLock.lock()
        _isRecording = true
        recordedPCM = Data()
        pendingAudio = Data()
        committedTranscript = ""
        partialText = ""
        loggedFirstBuffer = false
        stateLock.unlock()

        // Open the socket now so the handshake overlaps with the user speaking.
        connect()
        startAudioEngine()
        startChunkTimer()
    }

    func stopAndTranscribe() {
        let recordMs = Int((CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000)

        stateLock.lock()
        let wasRecording = _isRecording
        _isRecording = false
        awaitingFinal = true
        let raw = recordedPCM
        let failedEarly = connectionFailed
        stateLock.unlock()

        stopAudioEngine()
        stopChunkTimer()

        let rawMs = raw.count / 2 * 1000 / sampleRate
        log("stop recording [\(recordMs)ms held, \(rawMs)ms audio captured]")

        guard wasRecording else {
            finishFailure(pcm: Data(), "Recording did not start")
            return
        }
        guard !raw.isEmpty else {
            log("WARNING: no audio captured (mic produced 0 samples) — check mic input")
            finishSuccessEmpty()
            return
        }
        if failedEarly {
            // Socket never worked — save for retry so nothing is lost.
            finishFailure(pcm: raw, "Connection to OpenAI was lost")
            return
        }

        // Commit the final segment and wait for its transcript — but ONLY if the
        // socket is actually open. If it isn't yet (cold first-run handshake still
        // in flight), didOpen will flush the audio and commit for us. Sending a
        // commit into an unopened socket is lost and leaves the first try hanging.
        stateLock.lock(); let connected = isConnected; stateLock.unlock()
        if connected {
            send(["type": "input_audio_buffer.commit"])
        } else {
            log("release before socket open — deferring commit to didOpen")
        }

        // Safety net: don't wait forever. If the final `completed` never lands,
        // finalize with whatever we have (fixes "keeps loading").
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.log("final-transcript timeout — finalizing with partial")
            self.finalizeStreaming()
        }
        finalTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: timeout)
    }

    func cancel() {
        log("cancel")
        stateLock.lock()
        _isRecording = false
        finished = true
        awaitingFinal = false
        recordedPCM = Data()
        stateLock.unlock()
        stopChunkTimer()
        finalTimeout?.cancel(); finalTimeout = nil
        stopAudioEngine()
        teardownSocket()
    }

    // MARK: - Chunk timer (1-minute commits for long audio)

    private func startChunkTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + chunkInterval, repeating: chunkInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            let recording = self._isRecording
            let connected = self.isConnected
            self.stateLock.unlock()
            guard recording, connected else { return }
            self.log("chunk commit (~\(Int(self.chunkInterval))s)")
            self.send(["type": "input_audio_buffer.commit"])
            self.lastCommitTime = CFAbsoluteTimeGetCurrent()
        }
        chunkTimer = timer
        timer.resume()
    }

    private func stopChunkTimer() {
        chunkTimer?.cancel()
        chunkTimer = nil
    }

    // MARK: - Audio

    private func startAudioEngine() {
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            log("ERROR: invalid audio format")
            return
        }

        if let targetFormat = targetFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            if converter == nil {
                log("ERROR: could not create audio converter (\(inputFormat.sampleRate)Hz → 24kHz)")
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.audioLevelMonitor?.process(buffer: buffer)
            self?.captureAudio(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            log("mic engine started (in: \(Int(inputFormat.sampleRate))Hz \(inputFormat.channelCount)ch)")
        } catch {
            log("ERROR: engine start: \(error.localizedDescription)")
        }
    }

    private func stopAudioEngine() {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
    }

    /// Resample to 24 kHz mono PCM16, retain a copy, and stream it upstream.
    private func captureAudio(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        let recording = _isRecording
        stateLock.unlock()
        guard recording,
              let converter = converter,
              let targetFormat = targetFormat else { return }

        if !loggedFirstBuffer {
            loggedFirstBuffer = true
            log("first mic buffer received (\(buffer.frameLength) frames @ \(Int(buffer.format.sampleRate))Hz) — capture is live")
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var convError: NSError?
        let status = converter.convert(to: outBuffer, error: &convError) { _, inputStatus in
            if consumed { inputStatus.pointee = .noDataNow; return nil }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, outBuffer.frameLength > 0,
              let channelData = outBuffer.int16ChannelData else { return }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData[0], count: byteCount)

        stateLock.lock()
        recordedPCM.append(data)
        let connected = isConnected
        if !connected { pendingAudio.append(data) }
        stateLock.unlock()

        // Stream live so the socket stays active (no idle 1006 close).
        if connected {
            send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
        }
    }

    // MARK: - WebSocket

    private func connect() {
        // GA Realtime transcription session. Two things matter here:
        //  1. Use `?intent=transcription` — NOT `?model=`. The `?model=` param
        //     expects a voice-agent session model (gpt-realtime-2.x); passing the
        //     transcription model there is rejected. The transcription model goes
        //     in the session config (audio.input.transcription.model) instead.
        //  2. Do NOT send `OpenAI-Beta: realtime=v1` — the beta endpoint is retired
        //     and closes the socket with code 4000.
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session
        let task = session.webSocketTask(with: request)
        self.webSocket = task
        task.resume()
        receiveLoop()
    }

    private func sendSessionConfig() {
        // GA transcription session. EVERYTHING lives under session.audio.input —
        // including turn_detection (NOT session.turn_detection, which the server
        // rejects as "Unknown parameter: session.turn_detection"). turn_detection
        // = null disables VAD so we control commits (chunking / on release).
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": sampleRate],
                        "transcription": [
                            "model": model,
                            "language": "en"
                        ],
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ]
        send(config)
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        log("socket open")
        stateLock.lock()
        isConnected = true
        let backlog = pendingAudio
        pendingAudio = Data()
        let done = finished
        stateLock.unlock()

        guard !done else { return }

        sendSessionConfig()
        // Flush anything captured before the socket opened, in one append.
        if !backlog.isEmpty {
            send(["type": "input_audio_buffer.append", "audio": backlog.base64EncodedString()])
        }

        // First-try fix: if the user already RELEASED the key before the socket
        // finished opening (short utterance + cold TLS handshake), the commit in
        // stopAndTranscribe() was skipped because we weren't connected yet. Send
        // it now so the buffered audio is actually transcribed — otherwise the
        // first attempt hangs until timeout and only the REST Retry works.
        stateLock.lock(); let released = awaitingFinal; stateLock.unlock()
        if released {
            log("socket opened after release — committing buffered audio now")
            send(["type": "input_audio_buffer.commit"])
        }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        stateLock.lock(); let done = finished; stateLock.unlock()
        guard !done else { return }
        handleSocketFailure("Connection closed (code \(closeCode.rawValue))")
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.handleEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.handleEvent(text) }
                @unknown default: break
                }
                self.receiveLoop()
            case .failure(let error):
                self.handleSocketFailure(error.localizedDescription)
            }
        }
    }

    private func handleSocketFailure(_ message: String) {
        stateLock.lock()
        let done = finished
        let waiting = awaitingFinal
        isConnected = false
        connectionFailed = true
        stateLock.unlock()
        guard !done else { return }
        log("socket error: \(message)")
        // If the user already released, resolve now (deliver partial or fail);
        // otherwise stop() will handle it on release.
        if waiting { finalizeStreaming() }
    }

    private func handleEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "conversation.item.input_audio_transcription.delta":
            if let delta = json["delta"] as? String, !delta.isEmpty {
                stateLock.lock()
                partialText += delta
                let live = (committedTranscript + " " + partialText).trimmingCharacters(in: .whitespaces)
                stateLock.unlock()
                emitInterim(live)
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                stateLock.lock()
                if !transcript.isEmpty {
                    committedTranscript = (committedTranscript + " " + transcript).trimmingCharacters(in: .whitespaces)
                }
                partialText = ""
                let waiting = awaitingFinal
                let full = committedTranscript
                stateLock.unlock()
                log("segment completed (total \(full.count) chars)")
                if waiting {
                    finalizeStreaming()
                } else {
                    emitInterim(full)
                }
            }

        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "OpenAI error"
            log("API error: \(message)")
            stateLock.lock(); let waiting = awaitingFinal; stateLock.unlock()
            if waiting { finalizeStreaming() }

        default:
            break
        }
    }

    private func emitInterim(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onResult(text, false) }
    }

    // MARK: - Finalize

    /// Deliver the stitched transcript as the single final output. If we somehow
    /// have nothing, save the audio for retry instead of losing it.
    private func finalizeStreaming() {
        stateLock.lock()
        if finished { stateLock.unlock(); return }
        let full = (committedTranscript + " " + partialText).trimmingCharacters(in: .whitespacesAndNewlines)
        let pcm = recordedPCM
        stateLock.unlock()

        if !full.isEmpty {
            let ms = Int((CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000)
            log("DONE [\(ms)ms] → \"\(full)\"")
            finishSuccess(full)
        } else {
            log("no transcript produced — saving audio for retry")
            finishFailure(pcm: pcm, "No transcript was produced")
        }
    }

    // MARK: - Terminal delivery

    private func finishSuccess(_ text: String) {
        stateLock.lock()
        if finished { stateLock.unlock(); return }
        finished = true
        awaitingFinal = false
        let pcm = recordedPCM
        stateLock.unlock()
        finalTimeout?.cancel(); finalTimeout = nil
        teardownSocket()

        // Persist the recording as a WAV so it can be kept in history. Best-effort.
        if let onAudioSaved = onAudioSaved, !pcm.isEmpty {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("echotype-hist-\(id.uuidString).wav")
            if (try? WavWriter.write(pcm16: pcm, sampleRate: sampleRate, channels: 1, to: url)) != nil {
                DispatchQueue.main.async { onAudioSaved(url) }
            }
        }

        DispatchQueue.main.async { [weak self] in self?.onResult(text, true) }
    }

    private func finishSuccessEmpty() {
        stateLock.lock()
        if finished { stateLock.unlock(); return }
        finished = true
        awaitingFinal = false
        stateLock.unlock()
        finalTimeout?.cancel(); finalTimeout = nil
        teardownSocket()
        DispatchQueue.main.async { [weak self] in self?.onResult("", true) }
    }

    /// Failure with in-memory PCM: write a WAV first, then report.
    private func finishFailure(pcm: Data, _ message: String) {
        guard !pcm.isEmpty else {
            log("FAILED (no audio): \(message)")
            finishSuccessEmpty()
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("echotype-\(id.uuidString).wav")
        do {
            try WavWriter.write(pcm16: pcm, sampleRate: sampleRate, channels: 1, to: url)
        } catch {
            log("FAILED and could not write WAV: \(error.localizedDescription)")
            finishSuccessEmpty()
            return
        }
        finishFailure(savedURL: url, message)
    }

    /// Failure with an already-written WAV on disk.
    private func finishFailure(savedURL url: URL, _ message: String) {
        stateLock.lock()
        if finished { stateLock.unlock(); return }
        finished = true
        awaitingFinal = false
        stateLock.unlock()
        finalTimeout?.cancel(); finalTimeout = nil
        teardownSocket()
        log("FAILED: \(message) (audio saved for retry)")
        DispatchQueue.main.async { [weak self] in self?.onFailure(url, message) }
    }

    private func teardownSocket() {
        stateLock.lock(); isConnected = false; stateLock.unlock()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    // MARK: - Send helper

    private func send(_ payload: [String: Any]) {
        guard let socket = webSocket,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] error in
            guard let self = self, let error = error else { return }
            self.handleSocketFailure(error.localizedDescription)
        }
    }
}
