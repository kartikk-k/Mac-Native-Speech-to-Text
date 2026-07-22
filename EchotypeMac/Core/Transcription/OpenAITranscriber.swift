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

    /// Streaming transcription. Uploads the WAV with `stream=true` and reports
    /// partial text via `onDelta` as the server transcribes, then the final text
    /// via `completion`. This is what makes dictation feel fast — text appears
    /// progressively instead of after one long blocking request.
    ///
    /// Falls back to a clear failure on any error; the caller keeps the audio for
    /// retry. `onDelta` and `completion` are delivered on the main queue.
    static func transcribeStreaming(fileURL url: URL,
                                    apiKey: String,
                                    model: String,
                                    onDelta: @escaping (String) -> Void,
                                    completion: @escaping (Result<String, TranscribeError>) -> Void) {
        guard let wavData = try? Data(contentsOf: url) else {
            deliver(.failure(TranscribeError(message: "Could not read audio file")), completion)
            return
        }
        guard !apiKey.isEmpty else {
            deliver(.failure(TranscribeError(message: "No OpenAI API key set")), completion)
            return
        }
        guard wavData.count <= maxUploadBytes else {
            let mb = wavData.count / (1024 * 1024)
            deliver(.failure(TranscribeError(message: "Recording is too long to transcribe (\(mb) MB, max 25 MB)")), completion)
            return
        }

        let sizeMB = Double(wavData.count) / (1024 * 1024)
        AppLog.shared.log("OpenAI", String(format: "stream upload %.2f MB, model=%@", sizeMB, model))

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("response_format", "json")
        field("stream", "true")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let started = CFAbsoluteTimeGetCurrent()
        Task {
            do {
                let (bytes, response) = try await streamSession.bytes(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    // Error responses aren't SSE — drain and parse as JSON.
                    var data = Data()
                    for try await b in bytes { data.append(b) }
                    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    let errObj = json?["error"] as? [String: Any]
                    let msg = (errObj?["message"] as? String) ?? "HTTP \(http.statusCode)"
                    let outOfCredits = http.statusCode == 429 &&
                        ((errObj?["code"] as? String) == "insufficient_quota")
                    AppLog.shared.log("OpenAI", "stream error HTTP \(http.statusCode): \(msg)")
                    deliver(.failure(TranscribeError(message: outOfCredits ? "Out of OpenAI credits" : msg)), completion)
                    return
                }

                var accumulated = ""
                var final: String?
                var firstDeltaLogged = false
                for try await line in bytes.lines {
                    // SSE: we only care about `data:` payloads.
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { break }
                    guard let d = payload.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let type = obj["type"] as? String else { continue }
                    switch type {
                    case "transcript.text.delta":
                        if let delta = obj["delta"] as? String, !delta.isEmpty {
                            accumulated += delta
                            if !firstDeltaLogged {
                                firstDeltaLogged = true
                                let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
                                AppLog.shared.log("OpenAI", "first delta after \(ms)ms")
                            }
                            let snapshot = accumulated
                            DispatchQueue.main.async { onDelta(snapshot) }
                        }
                    case "transcript.text.done":
                        final = (obj["text"] as? String) ?? accumulated
                    default:
                        break
                    }
                }
                let result = (final ?? accumulated).trimmingCharacters(in: .whitespacesAndNewlines)
                let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
                AppLog.shared.log("OpenAI", "stream done in \(ms)ms, \(result.count) chars")
                deliver(.success(result), completion)
            } catch {
                AppLog.shared.log("OpenAI", "stream failed: \(error.localizedDescription)")
                deliver(.failure(TranscribeError(message: error.localizedDescription)), completion)
            }
        }
    }

    /// Separate session for the streaming path — no resource timeout cap so the
    /// SSE stream can run to completion.
    private static let streamSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        return URLSession(configuration: config)
    }()

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
