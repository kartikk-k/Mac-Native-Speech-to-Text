//
//  HistoryTabView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  A record of the user's last 100 transcriptions. Each row shows when it was
//  recorded, how long, word count, the model, the raw and cleaned text, and
//  gives Play / Copy / Retry (re-run grammar+rephrase) / Delete actions.
//

import SwiftUI
import AppKit

struct HistoryTabView: View {
    @EnvironmentObject private var historyStore: HistoryStore

    @State private var copiedID: UUID?
    @State private var retryingID: UUID?
    @State private var retryNoticeID: UUID?
    @State private var expandedIDs: Set<UUID> = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("History")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Your last \(HistoryStore.maxEntries) transcriptions — replay the audio, copy, or re-run cleanup.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    Spacer()
                    if !historyStore.entries.isEmpty {
                        dsCardButton(icon: "trash", label: "Clear all") {
                            historyStore.clearAll()
                        }
                    }
                }
                .padding(.bottom, 20)

                if historyStore.entries.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(historyStore.entries) { entry in
                            row(for: entry)
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34))
                .foregroundStyle(Color.white.opacity(0.5))
            Text("No transcriptions yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
            Text("Everything you dictate will show up here.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func row(for entry: HistoryEntry) -> some View {
        let isExpanded = expandedIDs.contains(entry.id)
        return dsCard {
            VStack(alignment: .leading, spacing: 8) {
                // Header: date + metadata chips + actions
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.white)
                        HStack(spacing: 8) {
                            metaChip(icon: "textformat.123", text: "\(entry.wordCount) words")
                            if entry.durationSeconds > 0 {
                                metaChip(icon: "timer", text: durationText(entry.durationSeconds))
                            }
                            if entry.wasCleaned {
                                metaChip(icon: "wand.and.stars", text: cleanupLabel(entry))
                            }
                        }
                    }
                    Spacer()
                    rowActions(for: entry)
                }

                // The inserted text (cleaned if present).
                Text(entry.finalText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .textSelection(.enabled)
                    .lineLimit(isExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)

                // If cleanup changed the text, offer a raw/cleaned comparison.
                if entry.wasCleaned {
                    Button(isExpanded ? "Hide original" : "Show original (raw)") {
                        if isExpanded { expandedIDs.remove(entry.id) } else { expandedIDs.insert(entry.id) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))

                    if isExpanded {
                        Text(entry.rawText)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .textSelection(.enabled)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func rowActions(for entry: HistoryEntry) -> some View {
        HStack(spacing: 8) {
            if entry.hasAudio, let url = historyStore.audioURL(for: entry) {
                dsCardButton(icon: "play.fill", label: "Play") {
                    AudioPreviewPlayer.shared.play(url: url)
                }
                // Re-transcribe the saved audio; result is copied to the clipboard.
                if retryingID == entry.id {
                    HStack(spacing: 6) {
                        LoadingSpinner(size: 12, lineWidth: 1.8)
                        Text("Retrying")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                } else {
                    dsCardButton(icon: retryNoticeID == entry.id ? "checkmark" : "arrow.clockwise",
                                 label: retryNoticeID == entry.id ? "Copied" : "Retry") {
                        retry(entry, url: url)
                    }
                }
            }
            dsCardButton(icon: copiedID == entry.id ? "checkmark" : "doc.on.doc",
                         label: copiedID == entry.id ? "Copied" : "Copy") {
                copy(entry.finalText, id: entry.id)
            }
            Button {
                historyStore.remove(entry)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    /// Re-transcribe the saved audio over REST and copy the fresh text.
    private func retry(_ entry: HistoryEntry, url: URL) {
        retryingID = entry.id
        FileTranscriber.transcribe(url: url, provider: .gptRealtime, model: entry.model) { result in
            retryingID = nil
            if case .success(let text) = result {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let pb = NSPasteboard.general
                    pb.clearContents(); pb.setString(trimmed, forType: .string)
                    retryNoticeID = entry.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if retryNoticeID == entry.id { retryNoticeID = nil }
                    }
                }
            }
        }
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10.5))
        }
        .foregroundStyle(Color.white.opacity(0.5))
    }

    private func cleanupLabel(_ entry: HistoryEntry) -> String {
        switch (entry.grammarApplied, entry.rephraseApplied) {
        case (true, true): return "Grammar + rephrase"
        case (true, false): return "Grammar"
        case (false, true): return "Rephrase"
        default: return "Cleaned"
        }
    }

    private func durationText(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let m = Int(seconds) / 60, s = Int(seconds) % 60
        return "\(m)m \(s)s"
    }

    private func copy(_ text: String, id: UUID) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedID == id { copiedID = nil }
        }
    }
}

#Preview("History") {
    HistoryTabView()
        .environmentObject(HistoryStore())
        .frame(width: 700, height: 560)
        .background(Color.black)
}
