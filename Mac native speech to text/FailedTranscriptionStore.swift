//
//  FailedTranscriptionStore.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Keeps a local history of recordings whose transcription failed (network
//  drop, OpenAI outage, etc.) so the user never loses the audio and can retry
//  later. Audio files live under Application Support; metadata is a small JSON.
//

import Foundation

struct FailedTranscription: Identifiable, Codable, Equatable {
    let id: UUID
    /// File name (not full path) of the audio inside the store directory.
    let audioFileName: String
    /// TranscriptionProvider rawValue used when it failed.
    let provider: String
    let model: String
    let createdAt: Date
    var errorMessage: String

    var providerDisplayName: String {
        (TranscriptionProvider(rawValue: provider) ?? .native).displayName
    }
}

final class FailedTranscriptionStore: ObservableObject {
    @Published private(set) var items: [FailedTranscription] = []

    private let fileManager = FileManager.default

    init() {
        load()
    }

    /// Directory holding audio files and the metadata index.
    var directory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = base
            .appendingPathComponent("Echotype", isDirectory: true)
            .appendingPathComponent("FailedTranscriptions", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }

    func audioURL(for item: FailedTranscription) -> URL {
        directory.appendingPathComponent(item.audioFileName)
    }

    /// Move an audio file into the store and record a failed entry.
    /// Returns the created entry (nil if the audio couldn't be imported).
    @discardableResult
    func add(sourceURL: URL, provider: TranscriptionProvider, model: String, error: String) -> FailedTranscription? {
        let id = UUID()
        let ext = sourceURL.pathExtension.isEmpty ? "wav" : sourceURL.pathExtension
        let fileName = "\(id.uuidString).\(ext)"
        let destination = directory.appendingPathComponent(fileName)

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            // Prefer moving; fall back to copying if the source is elsewhere.
            if sourceURL.path != destination.path {
                do {
                    try fileManager.moveItem(at: sourceURL, to: destination)
                } catch {
                    try fileManager.copyItem(at: sourceURL, to: destination)
                }
            }
        } catch {
            print("[FailedStore] could not import audio: \(error)")
            return nil
        }

        let entry = FailedTranscription(
            id: id,
            audioFileName: fileName,
            provider: provider.rawValue,
            model: model,
            createdAt: Date(),
            errorMessage: error
        )
        items.insert(entry, at: 0)
        save()
        return entry
    }

    func remove(_ item: FailedTranscription) {
        try? fileManager.removeItem(at: audioURL(for: item))
        items.removeAll { $0.id == item.id }
        save()
    }

    func item(withID id: UUID) -> FailedTranscription? {
        items.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([FailedTranscription].self, from: data) {
            // Drop entries whose audio no longer exists on disk.
            items = decoded.filter { fileManager.fileExists(atPath: directory.appendingPathComponent($0.audioFileName).path) }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
