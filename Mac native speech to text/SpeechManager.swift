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
    private let audioEngine = AVAudioEngine()
    private let onResult: (String, Bool) -> Void

    init(onResult: @escaping (String, Bool) -> Void) {
        self.onResult = onResult
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        requestPermissions()
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("Speech recognition authorized")
            case .denied:
                print("Speech recognition denied")
            case .restricted:
                print("Speech recognition restricted")
            case .notDetermined:
                print("Speech recognition not determined")
            @unknown default:
                break
            }
        }
    }

    func startRecognition() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                self.onResult(text, isFinal)
            }

            if error != nil || (result?.isFinal ?? false) {
                self.cleanupAudioEngine()
            }
        }
    }

    func stopRecognition() {
        recognitionRequest?.endAudio()
        cleanupAudioEngine()
    }

    private func cleanupAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
    }
}
