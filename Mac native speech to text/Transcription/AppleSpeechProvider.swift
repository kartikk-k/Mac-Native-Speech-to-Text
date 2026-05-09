//
//  AppleSpeechProvider.swift
//  Mac native speech to text
//
//  Wraps SFSpeechRecognizer to fit the TranscriptionProvider abstraction.
//  This is the default provider; it is always available.
//

import Foundation
import Speech
import AVFoundation

/// Apple's on-device SFSpeechRecognizer session. Logic mirrors the original
/// SpeechSession that lived inside SpeechManager.swift.
final class AppleSpeechSession: TranscriptionSession, @unchecked Sendable {
    let id = UUID()
    private let speechRecognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var completedSegments: [String] = []
    private var currentSegmentText = ""
    private var isTranscribing = false
    private var doneTimer: DispatchWorkItem?

    private var recordingStartTime: CFAbsoluteTime = 0
    private let onResult: (String, Bool) -> Void
    private weak var audioLevelMonitor: AudioLevelMonitor?

    var isRecording = false

    init(onResult: @escaping (String, Bool) -> Void, audioLevelMonitor: AudioLevelMonitor? = nil) {
        self.onResult = onResult
        self.audioLevelMonitor = audioLevelMonitor
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    private var fullText: String {
        let segments = completedSegments + (currentSegmentText.isEmpty ? [] : [currentSegmentText])
        return segments.joined(separator: " ")
    }

    func startRecording() {
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        print("[AppleSession \(id.uuidString.prefix(4))] start recording")

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("[AppleSession \(id.uuidString.prefix(4))] ERROR: invalid audio format")
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString + ".caf")
        self.tempFileURL = url

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
        } catch {
            print("[AppleSession \(id.uuidString.prefix(4))] ERROR: can't create file: \(error)")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
            self?.audioLevelMonitor?.process(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            isRecording = true
        } catch {
            print("[AppleSession \(id.uuidString.prefix(4))] ERROR: engine start: \(error)")
        }
    }

    func stopAndTranscribe() {
        let recordDuration = Int((CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000)
        print("[AppleSession \(id.uuidString.prefix(4))] stop recording [\(recordDuration)ms]")

        guard isRecording else {
            onResult("", true)
            return
        }

        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioFile = nil
        audioEngine = nil
        isRecording = false

        guard let url = tempFileURL else {
            onResult("", true)
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard fileSize > 0 else {
            onResult("", true)
            cleanupFile()
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            onResult("", true)
            cleanupFile()
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.addsPunctuation = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        isTranscribing = true
        completedSegments = []
        currentSegmentText = ""
        var lastResultText = ""
        let tStart = CFAbsoluteTimeGetCurrent()
        let tag = String(id.uuidString.prefix(4))

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, self.isTranscribing else { return }
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - tStart) * 1000)

            if let result = result {
                let text = result.bestTranscription.formattedString

                if text.count < lastResultText.count / 2 && !lastResultText.isEmpty {
                    self.completedSegments.append(lastResultText)
                    self.currentSegmentText = text
                } else {
                    self.currentSegmentText = text
                }
                lastResultText = text

                if result.isFinal {
                    self.completedSegments.append(text)
                    self.currentSegmentText = ""
                    lastResultText = ""
                    print("[AppleSession \(tag)] [\(elapsed)ms] segment finalized")
                }

                DispatchQueue.main.async {
                    self.onResult(self.fullText, false)
                }

                self.resetDoneTimer(tStart: tStart, recordDuration: recordDuration)
            }

            if let error = error {
                let code = (error as NSError).code
                print("[AppleSession \(tag)] [\(elapsed)ms] ended (code: \(code))")
                self.deliverFinal(tStart: tStart, recordDuration: recordDuration)
            }
        }
    }

    func cancel() {
        doneTimer?.cancel()
        doneTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        audioFile = nil
        isRecording = false
        isTranscribing = false
        cleanupFile()
    }

    private func resetDoneTimer(tStart: CFAbsoluteTime, recordDuration: Int) {
        doneTimer?.cancel()
        guard !completedSegments.isEmpty else { return }

        let timer = DispatchWorkItem { [weak self] in
            guard let self = self, self.isTranscribing else { return }
            self.recognitionTask?.cancel()
            self.deliverFinal(tStart: tStart, recordDuration: recordDuration)
        }
        doneTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: timer)
    }

    private func deliverFinal(tStart: CFAbsoluteTime, recordDuration: Int) {
        guard isTranscribing else { return }
        isTranscribing = false
        doneTimer?.cancel()
        doneTimer = nil

        let finalText = fullText
        let totalTime = Int((CFAbsoluteTimeGetCurrent() - tStart) * 1000)
        print("[AppleSession \(id.uuidString.prefix(4))] DONE: record=\(recordDuration)ms transcribe=\(totalTime)ms → \"\(finalText)\"")

        DispatchQueue.main.async {
            self.onResult(finalText, true)
        }
        cleanupFile()
    }

    private func cleanupFile() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }
}

final class AppleSpeechProvider: TranscriptionProvider, @unchecked Sendable {
    let id: TranscriptionProviderID = .appleNative

    var isReady: Bool { true }

    func makeSession(
        onResult: @escaping (String, Bool) -> Void,
        audioLevelMonitor: AudioLevelMonitor?
    ) -> TranscriptionSession? {
        return AppleSpeechSession(onResult: onResult, audioLevelMonitor: audioLevelMonitor)
    }
}
