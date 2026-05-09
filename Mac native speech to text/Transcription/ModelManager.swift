//
//  ModelManager.swift
//  Mac native speech to text
//
//  Tracks installation state for every catalog entry and drives the
//  download/uninstall flow. Observable so the Settings UI can react to
//  progress without polling.
//

import Foundation
import Combine

/// Per-model installation state surfaced to the UI.
enum ModelInstallState: Equatable {
    case notInstalled
    case downloading(progress: Double, currentFile: String)
    case installed
    case failed(String)
}

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var states: [String: ModelInstallState] = [:]

    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var sessions: [String: URLSession] = [:]

    init() {
        refreshAllStates()
    }

    /// Recomputes install state for every model in the registry.
    func refreshAllStates() {
        for model in ModelRegistry.availableModels {
            if case .downloading = states[model.id] {
                continue   // don't clobber an in-flight download
            }
            states[model.id] = model.isInstalled() ? .installed : .notInstalled
        }
    }

    func state(for modelID: String) -> ModelInstallState {
        states[modelID] ?? .notInstalled
    }

    func isInstalled(_ modelID: String) -> Bool {
        if case .installed = state(for: modelID) { return true }
        return false
    }

    /// Kicks off a sequential download of every file for `model`. If a
    /// download for this model is already in flight, this is a no-op.
    func install(_ model: ModelInfo) {
        if case .downloading = states[model.id] { return }
        if model.isInstalled() {
            states[model.id] = .installed
            return
        }

        let dir = model.localDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        states[model.id] = .downloading(progress: 0, currentFile: model.files.first?.localFilename ?? "")

        Task { [weak self] in
            await self?.downloadSequentially(model: model)
        }
    }

    /// Removes the model directory from disk. Active downloads are
    /// cancelled.
    func uninstall(_ model: ModelInfo) {
        cancelDownload(modelID: model.id)
        let dir = model.localDirectory()
        try? FileManager.default.removeItem(at: dir)
        states[model.id] = .notInstalled
    }

    func cancelDownload(modelID: String) {
        activeTasks[modelID]?.cancel()
        activeTasks[modelID] = nil
        sessions[modelID]?.invalidateAndCancel()
        sessions[modelID] = nil
        if case .downloading = states[modelID] {
            states[modelID] = .notInstalled
        }
    }

    // MARK: - Internal

    private func downloadSequentially(model: ModelInfo) async {
        let dir = model.localDirectory()
        let totalFiles = model.files.count

        for (index, file) in model.files.enumerated() {
            let dest = dir.appendingPathComponent(file.localFilename)
            if FileManager.default.fileExists(atPath: dest.path) { continue }

            let baseProgress = Double(index) / Double(totalFiles)
            let perFileShare = 1.0 / Double(totalFiles)

            do {
                try await downloadFile(
                    file: file,
                    destination: dest,
                    modelID: model.id
                ) { [weak self] fileProgress in
                    guard let self = self else { return }
                    let overall = baseProgress + perFileShare * fileProgress
                    self.states[model.id] = .downloading(progress: overall, currentFile: file.localFilename)
                }
            } catch {
                let reason = (error as NSError).localizedDescription
                states[model.id] = .failed(reason)
                return
            }
        }

        states[model.id] = model.isInstalled() ? .installed : .failed("Files missing after download.")
    }

    private func downloadFile(
        file: ModelFile,
        destination: URL,
        modelID: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        let session = URLSession(configuration: .default)
        sessions[modelID] = session
        defer {
            session.finishTasksAndInvalidate()
            sessions[modelID] = nil
            activeTasks[modelID] = nil
        }

        let (asyncBytes, response) = try await session.bytes(from: file.remoteURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "ModelManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP error fetching \(file.localFilename)"])
        }

        let expected = response.expectedContentLength > 0 ? response.expectedContentLength : file.approximateBytes
        let tmpURL = destination.appendingPathExtension("part")
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tmpURL) else {
            throw NSError(domain: "ModelManager", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot write to \(tmpURL.path)"])
        }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var lastReport = Date(timeIntervalSince1970: 0)

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if Date().timeIntervalSince(lastReport) > 0.1 {
                    let frac = expected > 0 ? min(1.0, Double(received) / Double(expected)) : 0
                    await progress(frac)
                    lastReport = Date()
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        try handle.close()

        // Atomic rename so a partial file is never observed as the final.
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tmpURL, to: destination)
        await progress(1.0)
    }
}
