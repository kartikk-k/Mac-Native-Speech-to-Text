//
//  GPTRealtimeSession.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Speech-to-text using OpenAI's Realtime transcription API.
//
//  We open a WebSocket to the realtime endpoint with `intent=transcription`,
//  so the session only ever produces text — no audio is generated or returned,
//  which is exactly what we want here. Microphone audio is resampled to
//  24 kHz mono PCM16 and streamed up as it's captured; on release we commit the
//  buffer and wait for the final transcript. Streaming while the user holds the
//  key is what makes this feel fast.
//
//  Every captured sample is also kept in memory so that, if the transcription
//  fails (dropped connection, OpenAI error, timeout), we can persist the audio
//  as a WAV and let the user retry it later — they never lose the recording.
//

import Foundation
import AVFoundation

final class GPTRealtimeSession: TranscriptionSession, @unchecked Sendable {
    let id = UUID()

    private let apiKey: String
    private let model: String
    private let onResult: (String, Bool) -> Void
    /// Called (on the main queue) when the capture couldn't be transcribed.
    /// Provides a WAV file of the recording and a human-readable reason.
    private let onFailure: (URL, String) -> Void
    private weak var audioLevelMonitor: AudioLevelMonitor?

    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let sampleRate = 24000
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 24000,
                                             channels: 1,
                                             interleaved: true)

    private var urlSession: URLSession?
    private var webSocket: URLSessionWebSocketTask?

    private let stateLock = NSLock()
    private var _isRecording = false
    private var isConnected = false
    private var awaitingFinal = false
    private var finished = false
    private var connectionFailed = false

    /// Interim (delta) transcript accumulated while the user is still speaking.
    private var partialText = ""
    /// Authoritative transcript from a `.completed` event.
    private var finalTranscript = ""
    /// Raw 24 kHz mono PCM16 of the whole capture, for retry-on-failure.
    private var recordedPCM = Data()

    private var recordingStartTime: CFAbsoluteTime = 0
    private var finalTimeout: DispatchWorkItem?

    private var tag: String { String(id.uuidString.prefix(4)) }

    var isRecording: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _isRecording
    }

    init(apiKey: String,
         model: String,
         onResult: @escaping (String, Bool) -> Void,
         onFailure: @escaping (URL, String) -> Void,
         audioLevelMonitor: AudioLevelMonitor? = nil) {
        self.apiKey = apiKey
        self.model = model
        self.onResult = onResult
        self.onFailure = onFailure
        self.audioLevelMonitor = audioLevelMonitor
    }

    // MARK: - TranscriptionSession

    func startRecording() {
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        print("[GPT \(tag)] start recording (model: \(model))")

        connect()

        stateLock.lock()
        _isRecording = true
        stateLock.unlock()

        startAudioEngine()
    }

    func stopAndTranscribe() {
        let recordMs = Int((CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000)
        print("[GPT \(tag)] stop recording [\(recordMs)ms]")

        stateLock.lock()
        let wasRecording = _isRecording
        let failedEarly = connectionFailed
        _isRecording = false
        awaitingFinal = true
        stateLock.unlock()

        stopAudioEngine()

        guard wasRecording else {
            finishFailure("Recording did not start")
            return
        }

        if failedEarly {
            finishFailure("Connection to OpenAI was lost")
            return
        }

        // Commit whatever we've streamed so the server transcribes it.
        send(["type": "input_audio_buffer.commit"])

        // Safety net: don't wait forever for the final transcript. Kept under
        // AppState's 10s global fallback so this path wins.
        let timeout = DispatchWorkItem { [weak self] in
            self?.finishFailure("Timed out waiting for transcription")
        }
        finalTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: timeout)
    }

    func cancel() {
        print("[GPT \(tag)] cancel")
        stateLock.lock()
        _isRecording = false
        finished = true
        awaitingFinal = false
        stateLock.unlock()

        finalTimeout?.cancel()
        finalTimeout = nil
        stopAudioEngine()
        teardownSocket()
    }

    // MARK: - Audio

    private func startAudioEngine() {
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            print("[GPT \(tag)] ERROR: invalid audio format")
            return
        }

        if let targetFormat = targetFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.audioLevelMonitor?.process(buffer: buffer)
            self?.streamAudio(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("[GPT \(tag)] ERROR: engine start: \(error)")
        }
    }

    private func stopAudioEngine() {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
    }

    /// Resample a captured buffer to 24 kHz mono PCM16, keep a copy for retry,
    /// and stream it upstream.
    private func streamAudio(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        let recording = _isRecording
        stateLock.unlock()
        guard recording,
              let converter = converter,
              let targetFormat = targetFormat else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var convError: NSError?
        let status = converter.convert(to: outBuffer, error: &convError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
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
        stateLock.unlock()

        if connected {
            send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
        }
    }

    // MARK: - WebSocket

    private func connect() {
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        self.urlSession = session
        let task = session.webSocketTask(with: request)
        self.webSocket = task
        task.resume()

        // Configure the session first, then start receiving events.
        sendSessionConfig()
        stateLock.lock()
        isConnected = true
        stateLock.unlock()
        receiveLoop()
    }

    private func sendSessionConfig() {
        // Transcription-only session: text out, no audio generation. Turn
        // detection is disabled so we control when the buffer is committed
        // (on key release), matching the app's hold-to-talk model.
        let config: [String: Any] = [
            "type": "transcription_session.update",
            "session": [
                "input_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": model,
                    "language": "en"
                ],
                "turn_detection": NSNull()
            ]
        ]
        send(config)
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleEvent(text)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure(let error):
                self.handleSocketFailure(error.localizedDescription)
            }
        }
    }

    private func handleSocketFailure(_ message: String) {
        stateLock.lock()
        let done = self.finished
        let waiting = self.awaitingFinal
        self.isConnected = false
        self.connectionFailed = true
        stateLock.unlock()
        guard !done else { return }
        print("[GPT \(tag)] socket error: \(message)")
        // If the user has already released, resolve now; otherwise stop() will
        // resolve as a failure once they let go.
        if waiting { finishFailure("Connection to OpenAI failed") }
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
                let interim = finalTranscript.isEmpty ? partialText : finalTranscript
                stateLock.unlock()
                emitInterim(interim)
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                stateLock.lock()
                finalTranscript = transcript
                partialText = ""
                let waiting = awaitingFinal
                stateLock.unlock()
                print("[GPT \(tag)] transcript completed")
                if waiting {
                    finishSuccess(transcript)
                } else {
                    emitInterim(transcript)
                }
            }

        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "OpenAI error"
            print("[GPT \(tag)] API error: \(message)")
            stateLock.lock()
            let waiting = awaitingFinal
            stateLock.unlock()
            if waiting { finishFailure(message) }

        default:
            break
        }
    }

    private func emitInterim(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onResult(text, false)
        }
    }

    // MARK: - Terminal delivery

    private func finishSuccess(_ text: String) {
        stateLock.lock()
        if finished { stateLock.unlock(); return }
        finished = true
        awaitingFinal = false
        stateLock.unlock()

        finalTimeout?.cancel()
        finalTimeout = nil

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000)
        print("[GPT \(tag)] DONE [\(totalMs)ms] → \"\(text)\"")

        teardownSocket()
        DispatchQueue.main.async { [weak self] in
            self?.onResult(text, true)
        }
    }

    private func finishFailure(_ message: String) {
        stateLock.lock()
        if finished { stateLock.unlock(); return }
        finished = true
        awaitingFinal = false
        let pcm = recordedPCM
        stateLock.unlock()

        finalTimeout?.cancel()
        finalTimeout = nil
        teardownSocket()

        print("[GPT \(tag)] FAILED: \(message)")

        // Nothing recorded — nothing to save or retry. Treat as an empty result.
        guard !pcm.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.onResult("", true)
            }
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("echotype-\(id.uuidString).wav")
        do {
            try WavWriter.write(pcm16: pcm, sampleRate: sampleRate, channels: 1, to: url)
        } catch {
            print("[GPT \(tag)] could not write WAV: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.onResult("", true)
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onFailure(url, message)
        }
    }

    private func teardownSocket() {
        stateLock.lock()
        isConnected = false
        stateLock.unlock()
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
