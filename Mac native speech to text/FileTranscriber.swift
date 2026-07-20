//
//  FileTranscriber.swift
//  Mac native speech to text
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

    private static func transcribeOpenAI(url: URL,
                                         model: String,
                                         completion: @escaping (Result<String, TranscriptionError>) -> Void) {
        guard let apiKey = TranscriptionSettings.openAIApiKey, !apiKey.isEmpty else {
            finish(.failure(TranscriptionError(message: "No OpenAI API key set")), completion)
            return
        }
        guard let audioData = try? Data(contentsOf: url) else {
            finish(.failure(TranscriptionError(message: "Could not read audio file")), completion)
            return
        }

        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", model)
        appendField("response_format", "json")
        appendField("language", "en")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                finish(.failure(TranscriptionError(message: error.localizedDescription)), completion)
                return
            }
            guard let data = data else {
                finish(.failure(TranscriptionError(message: "Empty response from OpenAI")), completion)
                return
            }

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let status = (response as? HTTPURLResponse)?.statusCode, status >= 400 {
                let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
                finish(.failure(TranscriptionError(message: message)), completion)
                return
            }
            if let text = json?["text"] as? String {
                finish(.success(text), completion)
            } else {
                finish(.failure(TranscriptionError(message: "Unexpected response from OpenAI")), completion)
            }
        }.resume()
    }
}
