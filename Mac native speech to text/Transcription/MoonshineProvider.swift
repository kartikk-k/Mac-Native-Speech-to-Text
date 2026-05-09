//
//  MoonshineProvider.swift
//  Mac native speech to text
//
//  Local transcription powered by Useful Sensors' Moonshine Tiny model.
//  Audio is captured at the device's native rate, resampled offline to
//  16 kHz mono float32, fed through the four-stage Moonshine ONNX pipeline
//  (preprocess → encode → uncached_decode → cached_decode loop), and the
//  resulting token ids are detokenized via tokenizer.json.
//
//  ONNX Runtime is provided by the Microsoft `onnxruntime-objc` Swift
//  package. The whole inference path is gated behind
//  `canImport(OnnxRuntimeBindings)` so the rest of the app keeps building
//  even if a developer hasn't yet added that SPM dependency.
//

import Foundation
import AVFoundation

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

// MARK: - Provider

final class MoonshineProvider: TranscriptionProvider, @unchecked Sendable {
    let id: TranscriptionProviderID = .moonshineTiny

    private let modelInfo: ModelInfo
    private let runtime: MoonshineRuntime?

    init(modelInfo: ModelInfo) {
        self.modelInfo = modelInfo
        self.runtime = MoonshineRuntime.tryLoad(modelDirectory: modelInfo.localDirectory())
    }

    var isReady: Bool { runtime != nil && modelInfo.isInstalled() }

    func makeSession(
        onResult: @escaping (String, Bool) -> Void,
        audioLevelMonitor: AudioLevelMonitor?
    ) -> TranscriptionSession? {
        guard let runtime = runtime else {
            DispatchQueue.main.async { onResult("", true) }
            return nil
        }
        return MoonshineSession(runtime: runtime, onResult: onResult, audioLevelMonitor: audioLevelMonitor)
    }
}

// MARK: - Session

final class MoonshineSession: TranscriptionSession, @unchecked Sendable {
    let id = UUID()
    private let runtime: MoonshineRuntime
    private let onResult: (String, Bool) -> Void
    private weak var audioLevelMonitor: AudioLevelMonitor?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var recordingStartTime: CFAbsoluteTime = 0
    private var isTranscribing = false

    var isRecording = false

    init(runtime: MoonshineRuntime,
         onResult: @escaping (String, Bool) -> Void,
         audioLevelMonitor: AudioLevelMonitor?) {
        self.runtime = runtime
        self.onResult = onResult
        self.audioLevelMonitor = audioLevelMonitor
    }

    func startRecording() {
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        let tag = String(id.uuidString.prefix(4))
        print("[Moonshine \(tag)] start recording")

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            print("[Moonshine \(tag)] ERROR: invalid audio format")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(id.uuidString + ".caf")
        self.tempFileURL = url

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
        } catch {
            print("[Moonshine \(tag)] ERROR: can't create file: \(error)")
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
            print("[Moonshine \(tag)] ERROR: engine start: \(error)")
        }
    }

    func stopAndTranscribe() {
        let recordDuration = Int((CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000)
        let tag = String(id.uuidString.prefix(4))
        print("[Moonshine \(tag)] stop recording [\(recordDuration)ms]")

        guard isRecording else {
            DispatchQueue.main.async { self.onResult("", true) }
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
            DispatchQueue.main.async { self.onResult("", true) }
            return
        }

        isTranscribing = true
        let runtime = self.runtime
        let onResult = self.onResult

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tStart = CFAbsoluteTimeGetCurrent()
            do {
                let samples = try MoonshineSession.loadAudioMono16k(from: url)
                guard !samples.isEmpty else {
                    DispatchQueue.main.async { onResult("", true) }
                    self?.cleanupFile()
                    return
                }
                let text = try runtime.transcribe(samples: samples)
                let totalTime = Int((CFAbsoluteTimeGetCurrent() - tStart) * 1000)
                print("[Moonshine \(tag)] DONE: record=\(recordDuration)ms transcribe=\(totalTime)ms → \"\(text)\"")
                DispatchQueue.main.async { onResult(text, true) }
            } catch {
                print("[Moonshine \(tag)] ERROR: \(error)")
                DispatchQueue.main.async { onResult("", true) }
            }
            self?.cleanupFile()
            self?.isTranscribing = false
        }
    }

    func cancel() {
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

    private func cleanupFile() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }

    /// Reads the recorded file and converts to a flat `[Float]` at 16 kHz
    /// mono, exactly the format Moonshine expects. AVAudioConverter handles
    /// both the channel mix-down and the sample-rate conversion.
    static func loadAudioMono16k(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionProviderError.audioFormatUnsupported
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw TranscriptionProviderError.audioFormatUnsupported
        }

        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0 else { return [] }

        let inputBufferCapacity: AVAudioFrameCount = 16384
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                                 frameCapacity: inputBufferCapacity) else {
            throw TranscriptionProviderError.audioFormatUnsupported
        }

        // Output buffer needs to hold the resampled equivalent of one input
        // chunk plus a little slack. The +1024 absorbs converter latency.
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBufferCapacity) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                  frameCapacity: outputCapacity) else {
            throw TranscriptionProviderError.audioFormatUnsupported
        }

        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(totalFrames) * ratio) + 1024)
        var inputDone = false

        while true {
            var status = AVAudioConverterOutputStatus.haveData
            var error: NSError?

            outputBuffer.frameLength = 0
            status = converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
                if inputDone {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: inputBuffer)
                } catch {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if inputBuffer.frameLength == 0 {
                    inputDone = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inputBuffer
            }

            if let error = error {
                throw TranscriptionProviderError.inferenceFailed("Audio conversion failed: \(error.localizedDescription)")
            }

            if outputBuffer.frameLength > 0,
               let channel = outputBuffer.floatChannelData?[0] {
                let count = Int(outputBuffer.frameLength)
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
            }

            if status == .endOfStream || status == .error { break }
            if status == .inputRanDry && inputDone { break }
        }

        return samples
    }
}

// MARK: - Runtime (ONNX inference)

/// Loads the four ONNX models + tokenizer once and runs inference. The
/// non-Moonshine code paths in the app never touch this type, so the
/// `canImport` guard is centralized here.
final class MoonshineRuntime: @unchecked Sendable {
    private let modelDirectory: URL
    private let tokenizer: MoonshineTokenizer
#if canImport(OnnxRuntimeBindings)
    private let env: ORTEnv
    private let preprocessSession: ORTSession
    private let encodeSession: ORTSession
    private let uncachedDecodeSession: ORTSession
    private let cachedDecodeSession: ORTSession
#endif

    /// Maximum tokens to generate per second of audio. Mirrors the upstream
    /// Moonshine reference implementation; English speech rarely exceeds
    /// ~6 tokens/second so this leaves headroom without runaway loops.
    private static let maxTokensPerSecond: Double = 6
    private static let minMaxTokens: Int = 32
    private static let absoluteMaxTokens: Int = 256

    /// Returns nil (rather than throwing) so the caller can decide whether
    /// to surface a UI error or fall back silently.
    static func tryLoad(modelDirectory: URL) -> MoonshineRuntime? {
        do {
            return try MoonshineRuntime(modelDirectory: modelDirectory)
        } catch {
            print("[Moonshine] runtime load failed: \(error)")
            return nil
        }
    }

    init(modelDirectory: URL) throws {
        self.modelDirectory = modelDirectory
        let tokenizerURL = modelDirectory.appendingPathComponent("tokenizer.json")
        guard FileManager.default.fileExists(atPath: tokenizerURL.path) else {
            throw TranscriptionProviderError.modelNotInstalled
        }
        self.tokenizer = try MoonshineTokenizer(tokenizerJSON: tokenizerURL)

#if canImport(OnnxRuntimeBindings)
        let env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let opts = try ORTSessionOptions()
        let pre = modelDirectory.appendingPathComponent("preprocess.onnx").path
        let enc = modelDirectory.appendingPathComponent("encode.onnx").path
        let unc = modelDirectory.appendingPathComponent("uncached_decode.onnx").path
        let cac = modelDirectory.appendingPathComponent("cached_decode.onnx").path
        for path in [pre, enc, unc, cac] {
            guard FileManager.default.fileExists(atPath: path) else {
                throw TranscriptionProviderError.modelNotInstalled
            }
        }
        self.env = env
        self.preprocessSession = try ORTSession(env: env, modelPath: pre, sessionOptions: opts)
        self.encodeSession = try ORTSession(env: env, modelPath: enc, sessionOptions: opts)
        self.uncachedDecodeSession = try ORTSession(env: env, modelPath: unc, sessionOptions: opts)
        self.cachedDecodeSession = try ORTSession(env: env, modelPath: cac, sessionOptions: opts)
#else
        throw TranscriptionProviderError.providerUnavailable("ONNX Runtime is not linked into this build.")
#endif
    }

#if canImport(OnnxRuntimeBindings)

    func transcribe(samples: [Float]) throws -> String {
        // 1. preprocess: (1, T) float audio → (1, F, dim) features
        let audioValue = try makeFloatTensor(values: samples, shape: [1, samples.count])
        let preInputs = try inputNames(of: preprocessSession)
        let preOutputs = try outputNames(of: preprocessSession)
        let preResult = try preprocessSession.run(
            withInputs: [preInputs[0]: audioValue],
            outputNames: Set(preOutputs),
            runOptions: nil
        )
        guard let features = preResult[preOutputs[0]] else {
            throw TranscriptionProviderError.inferenceFailed("preprocess produced no output")
        }
        let featuresShape = try features.tensorTypeAndShapeInfo().shape.map { $0.intValue }

        // 2. encode: (features, seq_len) → (1, S, dim)
        let seqLen = featuresShape.count >= 2 ? featuresShape[1] : 0
        let seqLenValue = try makeInt32Tensor(values: [Int32(seqLen)], shape: [1])

        let encInputs = try inputNames(of: encodeSession)
        let encOutputs = try outputNames(of: encodeSession)
        var encInputDict: [String: ORTValue] = [:]
        if encInputs.count >= 1 { encInputDict[encInputs[0]] = features }
        if encInputs.count >= 2 { encInputDict[encInputs[1]] = seqLenValue }
        let encResult = try encodeSession.run(
            withInputs: encInputDict,
            outputNames: Set(encOutputs),
            runOptions: nil
        )
        guard let encoderHidden = encResult[encOutputs[0]] else {
            throw TranscriptionProviderError.inferenceFailed("encode produced no output")
        }

        // 3. autoregressive decode (greedy)
        let durationSeconds = Double(samples.count) / 16_000.0
        let maxTokens = max(
            Self.minMaxTokens,
            min(Self.absoluteMaxTokens, Int(durationSeconds * Self.maxTokensPerSecond) + 8)
        )

        var generated: [Int] = []
        var nextInput = tokenizer.bosTokenID

        let uncachedInputs = try inputNames(of: uncachedDecodeSession)
        let uncachedOutputs = try outputNames(of: uncachedDecodeSession)
        let cachedInputs = try inputNames(of: cachedDecodeSession)
        let cachedOutputs = try outputNames(of: cachedDecodeSession)

        var kvCache: [String: ORTValue] = [:]

        // The KV cache "past" inputs on cached_decode start after the
        // positional inputs (tokens + encoder_hidden, optionally seq_len).
        // We pair them with the "present" outputs of the previous step by
        // ordinal — Moonshine's export uses a stable order so this works
        // regardless of whether seq_len is a third positional input.
        let cachePastStart = cachedInputs.count - (uncachedOutputs.count - 1)

        for step in 0..<maxTokens {
            let tokenValue = try makeInt32Tensor(values: [Int32(nextInput)], shape: [1, 1])

            let result: [String: ORTValue]
            if step == 0 {
                var inputs: [String: ORTValue] = [:]
                if uncachedInputs.count >= 1 { inputs[uncachedInputs[0]] = tokenValue }
                if uncachedInputs.count >= 2 { inputs[uncachedInputs[1]] = encoderHidden }
                if uncachedInputs.count >= 3 { inputs[uncachedInputs[2]] = seqLenValue }
                result = try uncachedDecodeSession.run(
                    withInputs: inputs,
                    outputNames: Set(uncachedOutputs),
                    runOptions: nil
                )
            } else {
                var inputs: [String: ORTValue] = [:]
                if cachedInputs.count >= 1 { inputs[cachedInputs[0]] = tokenValue }
                if cachedInputs.count >= 2 { inputs[cachedInputs[1]] = encoderHidden }
                // If the cached decoder takes seq_len as a positional input
                // (3 fixed inputs before the cache), pass it; otherwise the
                // remaining inputs are all KV cache slots.
                if cachePastStart > 2, cachedInputs.count > 2 {
                    inputs[cachedInputs[2]] = seqLenValue
                }
                for (k, v) in kvCache { inputs[k] = v }
                result = try cachedDecodeSession.run(
                    withInputs: inputs,
                    outputNames: Set(cachedOutputs),
                    runOptions: nil
                )
            }

            // Pull logits (always the first output by Moonshine convention).
            let logitsName = (step == 0 ? uncachedOutputs : cachedOutputs).first ?? ""
            guard let logits = result[logitsName] else {
                throw TranscriptionProviderError.inferenceFailed("decoder produced no logits")
            }

            // Refresh the KV cache from this step's "present_*" outputs.
            kvCache.removeAll()
            let presentNames: [String]
            if step == 0 {
                presentNames = Array(uncachedOutputs.dropFirst())
            } else {
                presentNames = Array(cachedOutputs.dropFirst())
            }
            let pastNames = Array(cachedInputs.suffix(presentNames.count))
            for (past, present) in zip(pastNames, presentNames) {
                if let v = result[present] { kvCache[past] = v }
            }

            let token = try MoonshineRuntime.argmaxLastStep(logits: logits)
            if token == tokenizer.eosTokenID || token == tokenizer.padTokenID { break }
            generated.append(token)
            nextInput = token
        }

        return tokenizer.decode(generated)
    }

    // MARK: tensor helpers

    private func inputNames(of session: ORTSession) throws -> [String] {
        return try session.inputNames()
    }

    private func outputNames(of session: ORTSession) throws -> [String] {
        return try session.outputNames()
    }

    private func makeFloatTensor(values: [Float], shape: [Int]) throws -> ORTValue {
        let data = NSMutableData(length: values.count * MemoryLayout<Float>.size)!
        values.withUnsafeBufferPointer { buf in
            data.replaceBytes(in: NSRange(location: 0, length: data.length),
                              withBytes: buf.baseAddress!)
        }
        let dims = shape.map { NSNumber(value: $0) }
        return try ORTValue(tensorData: data,
                            elementType: ORTTensorElementDataType.float,
                            shape: dims)
    }

    private func makeInt32Tensor(values: [Int32], shape: [Int]) throws -> ORTValue {
        let data = NSMutableData(length: values.count * MemoryLayout<Int32>.size)!
        values.withUnsafeBufferPointer { buf in
            data.replaceBytes(in: NSRange(location: 0, length: data.length),
                              withBytes: buf.baseAddress!)
        }
        let dims = shape.map { NSNumber(value: $0) }
        return try ORTValue(tensorData: data,
                            elementType: ORTTensorElementDataType.int32,
                            shape: dims)
    }

    private static func argmaxLastStep(logits: ORTValue) throws -> Int {
        let info = try logits.tensorTypeAndShapeInfo()
        let shape = info.shape.map { $0.intValue }
        guard shape.count >= 2 else {
            throw TranscriptionProviderError.inferenceFailed("logits has unexpected rank \(shape.count)")
        }
        let vocab = shape.last ?? 0
        guard vocab > 0 else {
            throw TranscriptionProviderError.inferenceFailed("logits vocab dim is zero")
        }

        let nsData = try logits.tensorData()
        let raw = Data(referencing: nsData)
        let totalElements = shape.reduce(1, *)
        let lastStepStart = totalElements - vocab

        var best: Int = 0
        var bestVal: Float = -.greatestFiniteMagnitude
        raw.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) in
            let floats = rawBuf.bindMemory(to: Float.self)
            for i in 0..<vocab {
                let v = floats[lastStepStart + i]
                if v > bestVal { bestVal = v; best = i }
            }
        }
        return best
    }

#else

    func transcribe(samples: [Float]) throws -> String {
        throw TranscriptionProviderError.providerUnavailable(
            "ONNX Runtime is not linked into this build. Add the onnxruntime-objc Swift package to enable Moonshine."
        )
    }

#endif
}
