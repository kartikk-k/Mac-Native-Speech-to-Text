//
//  AppLog.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  A tiny in-app logger. Everything that used to only `print()` to the Xcode
//  console now also lands here, so the running app can show a scrollable log and
//  a "Copy" button — the user can copy the log and paste it back for debugging
//  without needing Xcode attached.
//
//  Thread-safe, capped ring buffer. `entriesText` is what the Copy button uses.
//

import Foundation
import Combine

final class AppLog: ObservableObject {
    static let shared = AppLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let message: String
    }

    /// Newest-last. Published so the Logs view updates live. Only ever written on
    /// the main thread; the authoritative buffer is `storage` (lock-guarded).
    @Published private(set) var entries: [Entry] = []

    /// The real buffer. `log()` writes here under `lock` from ANY thread without
    /// touching the main queue, so logging can never stall the main run loop
    /// (critical — the global hotkey tap must never be starved). The @Published
    /// mirror is refreshed at most ~10×/sec via a coalesced flush.
    private var storage: [Entry] = []
    private var flushScheduled = false

    private let lock = NSLock()
    private let maxEntries = 2000

    private init() {}

    /// Log a line. Safe to call from any thread. Also mirrors to the console.
    /// Does NOT dispatch to the main queue per call — updates are coalesced.
    func log(_ category: String, _ message: String) {
        let entry = Entry(date: Date(), category: category, message: message)
        print("[\(category)] \(message)")

        lock.lock()
        storage.append(entry)
        if storage.count > maxEntries {
            storage.removeFirst(storage.count - maxEntries)
        }
        let needsFlush = !flushScheduled
        if needsFlush { flushScheduled = true }
        lock.unlock()

        guard needsFlush else { return }
        // Coalesce: refresh the published mirror once per ~100ms, no matter how
        // many log lines arrive in that window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let snapshot = self.storage
            self.flushScheduled = false
            self.lock.unlock()
            self.entries = snapshot
        }
    }

    func clear() {
        lock.lock(); storage = []; lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.entries = [] }
    }

    /// Full log as plain text, oldest-first — what the Copy button puts on the pasteboard.
    var entriesText: String {
        lock.lock(); let snapshot = storage; lock.unlock()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return snapshot.map { e in
            "\(formatter.string(from: e.date)) [\(e.category)] \(e.message)"
        }.joined(separator: "\n")
    }
}
