//
//  FileTranscriber.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Transcribes an already-recorded audio file. Used to retry failed captures.
//  GPT-Realtime failures retry against OpenAI's REST transcription endpoint
//  (simple and reliable for a whole-file upload); native failures re-run the
//  on-device recognizer over the file.
//

import Foundation
import Speech

enum FileTranscriber {

    /// Transcribe `url` using `provider`. Completion is delivered on the main
    /// queue with either the text or an error message.
    static func transcribe(url: URL,
                           provider: TranscriptionProvider,
                           model: String,
                           completion: @escaping (Result<String, TranscriptionError>) -> Void) {
        switch provider {
        case .native:
            transcribeNative(url: url, completion: completion)
        case .gptRealtime:
            transcribeOpenAI(url: url, model: model, completion: completion)
        }
    }

    struct TranscriptionError: Error {
        let message: String
    }

    private static func finish(_ result: Result<String, TranscriptionError>,
                               _ completion: @escaping (Result<String, TranscriptionError>) -> Void) {
        DispatchQueue.main.async { completion(result) }
    }

    // MARK: - Native (on-device)

    private static func transcribeNative(url: URL,
                                         completion: @escaping (Result<String, TranscriptionError>) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            finish(.failure(TranscriptionError(message: "Speech recognizer unavailable")), completion)
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        var delivered = false
        recognizer.recognitionTask(with: request) { result, error in
            if let result = result, result.isFinal {
                delivered = true
                finish(.success(result.bestTranscription.formattedString), completion)
            } else if let error = error, !delivered {
                delivered = true
                finish(.failure(TranscriptionError(message: error.localizedDescription)), completion)
            }
        }
    }

    // MARK: - OpenAI REST

    /// Delegates to the shared `OpenAITranscriber` so the live path and the retry
    /// path use exactly the same, tested upload code (long timeout, retry/backoff,
    /// 25 MB guard, logging).
    private static func transcribeOpenAI(url: URL,
                                         model: String,
                                         completion: @escaping (Result<String, TranscriptionError>) -> Void) {
        guard let apiKey = TranscriptionSettings.openAIApiKey, !apiKey.isEmpty else {
            finish(.failure(TranscriptionError(message: "No OpenAI API key set")), completion)
            return
        }
        OpenAITranscriber.transcribe(fileURL: url, apiKey: apiKey, model: model) { result in
            switch result {
            case .success(let text):
                finish(.success(text), completion)
            case .failure(let error):
                finish(.failure(TranscriptionError(message: error.message)), completion)
            }
        }
    }
}
