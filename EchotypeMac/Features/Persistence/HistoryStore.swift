//
//  HistoryStore.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  A rolling local history of the user's transcriptions — the last 100. Each
//  entry keeps the audio (so it can be replayed / re-run), the raw transcript,
//  the cleaned (grammar/rephrase) text if cleanup ran, and metadata (when, how
//  long, word count, which model, whether grammar/rephrase were applied).
//
//  Storage mirrors FailedTranscriptionStore: audio files + a JSON index under
//  Application Support. Oldest entries (and their audio) are pruned past 100.
//

import Foundation
import Combine

struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    /// Audio file name (not full path) inside the history directory. Empty if
    /// audio wasn't available for this entry.
    var audioFileName: String
    /// Verbatim transcript from the speech model (empty for a failed capture).
    let rawText: String
    /// Text after grammar/rephrase cleanup, if it ran (else same as raw).
    let cleanedText: String
    let grammarApplied: Bool
    let rephraseApplied: Bool
    /// Transcription model used (e.g. gpt-realtime-whisper).
    let model: String
    let createdAt: Date
    /// Recording length in seconds (0 if unknown).
    let durationSeconds: Double
    /// True when transcription failed — this entry is a saved recording awaiting
    /// a retry rather than a completed transcript.
    var failed: Bool = false
    /// Human-readable failure reason (only when `failed`).
    var errorMessage: String = ""
    /// Provider rawValue used for the capture (for retry).
    var provider: String = TranscriptionProvider.gptRealtime.rawValue

    /// The text actually inserted (cleaned if it differs, else raw).
    var finalText: String { cleanedText.isEmpty ? rawText : cleanedText }

    var wordCount: Int {
        finalText.split { $0.isWhitespace || $0.isNewline }.count
    }

    var hasAudio: Bool { !audioFileName.isEmpty }
    /// True when cleanup actually changed the text.
    var wasCleaned: Bool { !failed && !cleanedText.isEmpty && cleanedText != rawText }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    /// Hard cap on retained entries (and their audio files).
    static let maxEntries = 100

    private let fileManager = FileManager.default

    init() {
        load()
    }

    var directory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = base
            .appendingPathComponent("Echotype", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    func audioURL(for entry: HistoryEntry) -> URL? {
        guard entry.hasAudio else { return nil }
        return directory.appendingPathComponent(entry.audioFileName)
    }

    /// Record a completed transcription. `audioSource`, if provided, is COPIED
    /// into the history directory (the caller keeps ownership of the original).
    @discardableResult
    func add(rawText: String,
             cleanedText: String,
             grammarApplied: Bool,
             rephraseApplied: Bool,
             model: String,
             durationSeconds: Double,
             audioSource: URL?) -> HistoryEntry? {
        let trimmedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else { return nil }

        let id = UUID()
        var fileName = ""
        if let source = audioSource, fileManager.fileExists(atPath: source.path) {
            let ext = source.pathExtension.isEmpty ? "wav" : source.pathExtension
            fileName = "\(id.uuidString).\(ext)"
            let dest = directory.appendingPathComponent(fileName)
            do {
                if fileManager.fileExists(atPath: dest.path) { try fileManager.removeItem(at: dest) }
                try fileManager.copyItem(at: source, to: dest)
            } catch {
                print("[HistoryStore] could not copy audio: \(error)")
                fileName = ""
            }
        }

        let entry = HistoryEntry(
            id: id,
            audioFileName: fileName,
            rawText: trimmedRaw,
            cleanedText: cleanedText.trimmingCharacters(in: .whitespacesAndNewlines),
            grammarApplied: grammarApplied,
            rephraseApplied: rephraseApplied,
            model: model,
            createdAt: Date(),
            durationSeconds: durationSeconds
        )
        entries.insert(entry, at: 0)
        prune()
        save()
        return entry
    }

    /// Record a FAILED capture so it lives in history alongside successes, with
    /// its audio kept for retry.
    @discardableResult
    func addFailed(reason: String,
                   provider: TranscriptionProvider,
                   model: String,
                   durationSeconds: Double,
                   audioSource: URL?) -> HistoryEntry? {
        let id = UUID()
        var fileName = ""
        if let source = audioSource, fileManager.fileExists(atPath: source.path) {
            let ext = source.pathExtension.isEmpty ? "wav" : source.pathExtension
            fileName = "\(id.uuidString).\(ext)"
            let dest = directory.appendingPathComponent(fileName)
            do {
                if fileManager.fileExists(atPath: dest.path) { try fileManager.removeItem(at: dest) }
                // Move (not copy) — the source is a temp failure WAV we own.
                try fileManager.moveItem(at: source, to: dest)
            } catch {
                try? fileManager.copyItem(at: source, to: dest)
            }
        }
        guard !fileName.isEmpty else { return nil }  // nothing to retry without audio

        let entry = HistoryEntry(
            id: id, audioFileName: fileName, rawText: "", cleanedText: "",
            grammarApplied: false, rephraseApplied: false, model: model,
            createdAt: Date(), durationSeconds: durationSeconds,
            failed: true, errorMessage: reason, provider: provider.rawValue
        )
        entries.insert(entry, at: 0)
        prune()
        save()
        return entry
    }

    /// After a successful retry of a failed entry, fill in the transcript and
    /// clear the failed state (in place, keeping its position/audio).
    func markTranscribed(_ id: UUID, rawText: String, cleanedText: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let old = entries[idx]
        entries[idx] = HistoryEntry(
            id: old.id, audioFileName: old.audioFileName,
            rawText: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
            cleanedText: cleanedText.trimmingCharacters(in: .whitespacesAndNewlines),
            grammarApplied: old.grammarApplied, rephraseApplied: old.rephraseApplied,
            model: old.model, createdAt: old.createdAt, durationSeconds: old.durationSeconds,
            failed: false, errorMessage: "", provider: old.provider
        )
        save()
    }

    func remove(_ entry: HistoryEntry) {
        if let url = audioURL(for: entry) { try? fileManager.removeItem(at: url) }
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        for entry in entries {
            if let url = audioURL(for: entry) { try? fileManager.removeItem(at: url) }
        }
        entries.removeAll()
        save()
    }

    // MARK: - Private

    /// Keep only the newest `maxEntries`, deleting pruned entries' audio.
    private func prune() {
        guard entries.count > Self.maxEntries else { return }
        let dropped = entries[Self.maxEntries...]
        for entry in dropped {
            if let url = audioURL(for: entry) { try? fileManager.removeItem(at: url) }
        }
        entries = Array(entries.prefix(Self.maxEntries))
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
