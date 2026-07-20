//
//  GPTRealtimeSession.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Speech-to-text using OpenAI. Despite the name, this no longer uses the
//  Realtime WebSocket: this app records the whole utterance while a key is held
//  and sends it once on release (it never needs live transcript deltas). For
//  that pattern the reliable, cheaper path is the REST transcription endpoint
//  (POST /v1/audio/transcriptions) — see OpenAITranscriber for the reasoning.
//
//  Flow: capture mic audio → resample to 24 kHz mono PCM16 → on release, gently
//  trim long silences, write a WAV, and POST it. If it fails, the WAV is handed
//  to the failed-capture store so the user can retry later — the audio is never
//  lost. The class name and TranscriptionSession interface are kept so the rest
//  of the app is unchanged.
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

    private let stateLock = NSLock()
    private var _isRecording = false
    private var finished = false

    /// Raw 24 kHz mono PCM16 of the whole capture.
    private var recordedPCM = Data()
    /// Log the first captured buffer once, to confirm the mic is producing audio.
    private var loggedFirstBuffer = false

    private var recordingStartTime: CFAbsoluteTime = 0

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
        log("start recording (model: \(model))")

        stateLock.lock()
        _isRecording = true
        recordedPCM = Data()
        loggedFirstBuffer = false
        stateLock.unlock()

        startAudioEngine()
    }

    func stopAndTranscribe() {
        let recordMs = Int((CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000)

        stateLock.lock()
        let wasRecording = _isRecording
        _isRecording = false
        let raw = recordedPCM
        stateLock.unlock()

        stopAudioEngine()

        let rawMs = raw.count / 2 * 1000 / sampleRate
        log("stop recording [\(recordMs)ms held, \(rawMs)ms audio captured]")

        guard wasRecording else {
            finishFailure(pcm: Data(), "Recording did not start")
            return
        }
        // An empty capture means the mic produced no audio (engine race, no input
        // device, permissions). Surface it as an empty result — there is genuinely
        // nothing to transcribe or save — but log loudly so the Logs tab shows it.
        guard !raw.isEmpty else {
            log("WARNING: no audio was captured (mic produced 0 samples) — check mic input")
            finishSuccessEmpty()
            return
        }

        // Gently trim long thinking-pauses (never drops quiet speech — see
        // SilenceTrimmer). Then write a WAV and upload it.
        let trimmed = SilenceTrimmer.trim(pcm16: raw, sampleRate: sampleRate)
        let trimmedMs = trimmed.count / 2 * 1000 / sampleRate
        log("after trim: \(trimmedMs)ms (removed \(rawMs - trimmedMs)ms)")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("echotype-\(id.uuidString).wav")
        do {
            try WavWriter.write(pcm16: trimmed, sampleRate: sampleRate, channels: 1, to: url)
        } catch {
            log("could not write WAV: \(error.localizedDescription)")
            // Fall back to failure with the untrimmed audio so nothing is lost.
            finishFailure(pcm: raw, "Could not prepare audio")
            return
        }

        log("uploading to OpenAI…")
        // Retain self STRONGLY through the upload. If we used [weak self] and the
        // session were deallocated mid-upload (e.g. a new recording started), the
        // result would vanish silently — no transcript, no failure, nothing in the
        // failed list. Holding self guarantees exactly one terminal callback fires.
        OpenAITranscriber.transcribe(fileURL: url, apiKey: apiKey, model: model) { result in
            switch result {
            case .success(let text):
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.log("DONE → \"\(trimmedText)\"")
                try? FileManager.default.removeItem(at: url)
                self.finishSuccess(trimmedText)
            case .failure(let error):
                self.log("upload failed: \(error.message)")
                // Hand the already-written WAV to the failed-capture store for retry.
                self.finishFailure(savedURL: url, error.message)
            }
        }
    }

    func cancel() {
        log("cancel")
        stateLock.lock()
        _isRecording = false
        finished = true
        recordedPCM = Data()
        stateLock.unlock()
        stopAudioEngine()
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
                log("ERROR: could not create audio converter (in \(inputFormat.sampleRate)Hz → 24kHz)")
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

    /// Resample a captured buffer to 24 kHz mono PCM16 and accumulate it.
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
        stateLock.unlock()
    }

    // MARK: - Terminal delivery

    private func finishSuccess(_ text: String) {
        stateLock.lock()
        if finished { stateLock.unlock(); return }
        finished = true
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onResult(text, true) }
    }

    private func finishSuccessEmpty() {
        stateLock.lock()
        if finished { stateLock.unlock(); return }
        finished = true
        stateLock.unlock()
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
        stateLock.unlock()
        log("FAILED: \(message) (audio saved for retry)")
        DispatchQueue.main.async { [weak self] in self?.onFailure(url, message) }
    }
}
