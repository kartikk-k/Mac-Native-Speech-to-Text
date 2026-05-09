//
//  ModelRegistry.swift
//  Mac native speech to text
//
//  Static catalog of downloadable transcription models. Designed so adding
//  a new model only requires appending to `availableModels` — the rest of
//  the app (download UI, install state, provider lookup) reads off this
//  list.
//

import Foundation

/// One file that needs to live next to a model on disk. The file is
/// downloaded from `remoteURL` and stored at `localFilename` inside the
/// model's directory.
struct ModelFile: Identifiable, Hashable {
    let localFilename: String
    let remoteURL: URL
    /// Approximate size in bytes; used only for the progress UI tooltip.
    let approximateBytes: Int64

    var id: String { localFilename }
}

/// Catalog entry for a model the user can download.
struct ModelInfo: Identifiable, Hashable {
    let id: String
    let providerID: TranscriptionProviderID
    let displayName: String
    let provider: String           // e.g. "Useful Sensors"
    let description: String
    let licenseName: String
    let licenseURL: URL?
    let totalApproximateBytes: Int64
    let files: [ModelFile]

    /// Directory where this model's files live once installed.
    func localDirectory() -> URL {
        ModelStorage.modelsRoot.appendingPathComponent(id, isDirectory: true)
    }

    /// True if every file is on disk at the expected path.
    func isInstalled() -> Bool {
        let dir = localDirectory()
        for file in files {
            let path = dir.appendingPathComponent(file.localFilename)
            if !FileManager.default.fileExists(atPath: path.path) { return false }
        }
        return !files.isEmpty
    }
}

/// Resolves the on-disk root used for downloaded models. We prefer
/// Application Support so the data persists across app updates and is
/// excluded from iCloud-style backups by default.
enum ModelStorage {
    static var modelsRoot: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? fm.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "Echotype"
        let root = base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

enum ModelRegistry {
    /// All models known to the app. To add a new provider/model in the
    /// future, append a `ModelInfo` here and register the corresponding
    /// `TranscriptionProvider` in `SpeechManager`.
    static let availableModels: [ModelInfo] = [
        ModelInfo(
            id: "moonshine-tiny",
            providerID: .moonshineTiny,
            displayName: "Moonshine Tiny",
            provider: "Useful Sensors",
            description: "Fast on-device English speech recognition tuned for short utterances. ~30 MB on disk.",
            licenseName: "MIT",
            licenseURL: URL(string: "https://huggingface.co/UsefulSensors/moonshine-tiny"),
            totalApproximateBytes: 35_000_000,
            files: [
                ModelFile(
                    localFilename: "preprocess.onnx",
                    remoteURL: URL(string: "https://huggingface.co/UsefulSensors/moonshine/resolve/main/onnx/tiny/preprocess.onnx")!,
                    approximateBytes: 1_700_000
                ),
                ModelFile(
                    localFilename: "encode.onnx",
                    remoteURL: URL(string: "https://huggingface.co/UsefulSensors/moonshine/resolve/main/onnx/tiny/encode.onnx")!,
                    approximateBytes: 13_500_000
                ),
                ModelFile(
                    localFilename: "uncached_decode.onnx",
                    remoteURL: URL(string: "https://huggingface.co/UsefulSensors/moonshine/resolve/main/onnx/tiny/uncached_decode.onnx")!,
                    approximateBytes: 9_500_000
                ),
                ModelFile(
                    localFilename: "cached_decode.onnx",
                    remoteURL: URL(string: "https://huggingface.co/UsefulSensors/moonshine/resolve/main/onnx/tiny/cached_decode.onnx")!,
                    approximateBytes: 9_500_000
                ),
                ModelFile(
                    localFilename: "tokenizer.json",
                    remoteURL: URL(string: "https://huggingface.co/UsefulSensors/moonshine-tiny/resolve/main/tokenizer.json")!,
                    approximateBytes: 800_000
                ),
            ]
        )
    ]

    static func model(for id: TranscriptionProviderID) -> ModelInfo? {
        availableModels.first { $0.providerID == id }
    }
}
