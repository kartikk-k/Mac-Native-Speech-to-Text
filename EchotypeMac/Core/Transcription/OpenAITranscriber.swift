//
//  OpenAITranscriber.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  One place that talks to OpenAI's REST transcription endpoint
//  (POST /v1/audio/transcriptions). Both the live "hold-to-talk then send once"
//  path and the retry-a-saved-file path go through here.
//
//  WHY REST AND NOT THE REALTIME WEBSOCKET:
//  This app records the whole utterance while a key is held and only sends it
//  once, on release — it does not need live transcript deltas. OpenAI's own
//  guidance is to use the Realtime session only when you need live deltas from
//  streaming audio, and to use the file/request transcription endpoint for
//  upload-and-transcribe workflows. The WebSocket path caused "connection lost"
//  (idle socket → server closes with 1006) and first-attempt handshake races.
//  REST is the reliable, cheaper fit for this use case.
//
//  Limits (from the docs): 25 MB max upload; wav is an accepted format.
//

import Foundation

enum OpenAITranscriber {

    struct TranscribeError: Error {
        let message: String
    }

    /// 25 MB upload cap on /v1/audio/transcriptions.
    static let maxUploadBytes = 25 * 1024 * 1024

    /// Long-running session so large uploads aren't killed by the default 60s
    /// request timeout. Reused across calls and retries.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    /// Transcribe a WAV file at `url`. Completion is delivered on the main queue.
    static func transcribe(fileURL url: URL,
                           apiKey: String,
                           model: String,
                           completion: @escaping (Result<String, TranscribeError>) -> Void) {
        guard let data = try? Data(contentsOf: url) else {
            deliver(.failure(TranscribeError(message: "Could not read audio file")), completion)
            return
        }
        transcribe(wavData: data,
                   filename: url.lastPathComponent,
                   apiKey: apiKey,
                   model: model,
                   completion: completion)
    }

    /// Transcribe in-memory WAV bytes. Completion is delivered on the main queue.
    static func transcribe(wavData: Data,
                           filename: String,
                           apiKey: String,
                           model: String,
                           completion: @escaping (Result<String, TranscribeError>) -> Void) {
        guard !apiKey.isEmpty else {
            deliver(.failure(TranscribeError(message: "No OpenAI API key set")), completion)
            return
        }
        let sizeMB = Double(wavData.count) / (1024 * 1024)
        AppLog.shared.log("OpenAI", String(format: "upload %.2f MB, model=%@, file=%@", sizeMB, model, filename))

        guard wavData.count <= maxUploadBytes else {
            let mb = wavData.count / (1024 * 1024)
            deliver(.failure(TranscribeError(
                message: "Recording is too long to transcribe (\(mb) MB, max 25 MB)")), completion)
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

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Retry transient failures (network drop, 429, 5xx) with short backoff.
        send(request: request, attemptsLeft: 3, completion: completion)
    }

    private static func send(request: URLRequest,
                             attemptsLeft: Int,
                             completion: @escaping (Result<String, TranscribeError>) -> Void) {
        let attempt = 4 - attemptsLeft
        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            let transient = error != nil || status == 429 || (status.map { $0 >= 500 } ?? false)

            if transient && attemptsLeft > 1 {
                let delay = Double(attempt) * 1.5 + 1.0   // ~2.5s, 4s
                AppLog.shared.log("OpenAI", "attempt \(attempt) failed (\(error?.localizedDescription ?? "HTTP \(status ?? -1)")), retrying in \(String(format: "%.1f", delay))s")
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    send(request: request, attemptsLeft: attemptsLeft - 1, completion: completion)
                }
                return
            }

            if let error = error {
                AppLog.shared.log("OpenAI", "network error: \(error.localizedDescription)")
                deliver(.failure(TranscribeError(message: error.localizedDescription)), completion)
                return
            }
            guard let data = data else {
                deliver(.failure(TranscribeError(message: "Empty response from OpenAI")), completion)
                return
            }

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let status = status, status >= 400 {
                let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
                AppLog.shared.log("OpenAI", "API error (HTTP \(status)): \(message)")
                deliver(.failure(TranscribeError(message: message)), completion)
                return
            }
            if let text = json?["text"] as? String {
                AppLog.shared.log("OpenAI", "success, \(text.count) chars")
                deliver(.success(text), completion)
            } else {
                AppLog.shared.log("OpenAI", "unexpected response shape")
                deliver(.failure(TranscribeError(message: "Unexpected response from OpenAI")), completion)
            }
        }.resume()
    }

    private static func deliver(_ result: Result<String, TranscribeError>,
                                _ completion: @escaping (Result<String, TranscribeError>) -> Void) {
        DispatchQueue.main.async { completion(result) }
    }
}
