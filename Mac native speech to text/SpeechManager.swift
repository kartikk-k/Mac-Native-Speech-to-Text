//
//  SpeechManager.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Foundation
import Speech
import AVFoundation

class SpeechManager: @unchecked Sendable {
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private let onResult: (String, Bool) -> Void
    private var isRunning = false
    private var micAuthorized = false
    private var isStopping = false

    init(onResult: @escaping (String, Bool) -> Void) {
        self.onResult = onResult
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        print("[SpeechManager] init — recognizer available: \(speechRecognizer?.isAvailable ?? false)")
        print("[SpeechManager] supports on-device: \(speechRecognizer?.supportsOnDeviceRecognition ?? false)")

        requestPermissions()
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            print("[SpeechManager] speech auth status: \(status.rawValue) (3=authorized)")
        }

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            self.micAuthorized = granted
            print("[SpeechManager] microphone access granted: \(granted)")
        }
    }

    func startRecognition() {
        guard !isRunning else {
            print("[SpeechManager] startRecognition called but already running, ignoring")
            return
        }

        guard micAuthorized else {
            print("[SpeechManager] ERROR: microphone access not granted")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                self.micAuthorized = granted
                print("[SpeechManager] microphone re-request: \(granted)")
            }
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("[SpeechManager] ERROR: speechRecognizer nil or unavailable")
            return
        }

        print("[SpeechManager] --- Starting recognition ---")

        isStopping = false

        // Create a fresh audio engine every time to avoid stale inputNode state
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            print("[SpeechManager] using on-device recognition")
        } else {
            print("[SpeechManager] on-device not supported, using server")
        }

        self.recognitionRequest = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("[SpeechManager] audio format: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")

        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("[SpeechManager] ERROR: invalid audio format — no microphone?")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        print("[SpeechManager] audio tap installed")

        engine.prepare()

        do {
            try engine.start()
            isRunning = true
            print("[SpeechManager] audio engine started")
        } catch {
            print("[SpeechManager] ERROR: audio engine failed to start: \(error)")
            tearDown()
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                print("[SpeechManager] result: \"\(text)\" (final: \(isFinal))")
                self.onResult(text, isFinal)
            }

            if let error = error {
                let code = (error as NSError).code
                // Code 216 = "request was canceled" — expected when we call stopRecognition
                if code != 216 {
                    print("[SpeechManager] recognition error: \(error.localizedDescription) (code: \(code))")
                } else {
                    print("[SpeechManager] recognition cancelled (expected)")
                }
                self.tearDown()
            } else if result?.isFinal == true {
                print("[SpeechManager] final result received, tearing down")
                self.tearDown()
            }
        }
        print("[SpeechManager] recognition task created")
    }

    func stopRecognition() {
        print("[SpeechManager] --- Stopping recognition --- (isRunning: \(isRunning))")
        guard isRunning, !isStopping else {
            print("[SpeechManager] not running or already stopping, skip")
            return
        }
        isStopping = true

        // Stop audio first so no more buffers are appended
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            print("[SpeechManager] audio engine stopped")
        }

        // End audio on the request — this triggers the final result callback
        recognitionRequest?.endAudio()
        print("[SpeechManager] endAudio called, waiting for final result...")

        // Safety timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.isRunning == true {
                print("[SpeechManager] timeout — forcing teardown")
                self?.recognitionTask?.cancel()
                self?.tearDown()
            }
        }
    }

    private func tearDown() {
        guard isRunning else { return }
        print("[SpeechManager] tearDown")

        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        isRunning = false
        isStopping = false

        print("[SpeechManager] tearDown complete")
    }
}
