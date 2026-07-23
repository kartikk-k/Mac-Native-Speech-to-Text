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
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var player = AudioPreviewPlayer.shared

    @State private var copiedID: UUID?
    @State private var retryingID: UUID?
    @State private var retryNoticeID: UUID?
    @State private var expandedIDs: Set<UUID> = []
    @State private var search = ""
    @State private var confirmClear = false

    /// Entries matching the search box (matches transcript text).
    private var filtered: [HistoryEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return historyStore.entries }
        return historyStore.entries.filter {
            $0.finalText.lowercased().contains(q) || $0.rawText.lowercased().contains(q)
        }
    }

    /// Filtered entries grouped by day, newest day first, with a section title.
    private var grouped: [(title: String, entries: [HistoryEntry])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { day in
            (title: dayTitle(day), entries: groups[day] ?? [])
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("History")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Your last \(HistoryStore.maxEntries) transcriptions — replay, copy, or re-transcribe.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    Spacer()
                    if !historyStore.entries.isEmpty {
                        dsCardButton(icon: "trash", label: "Clear all") {
                            confirmClear = true
                        }
                    }
                }
                .padding(.bottom, 16)

                if !historyStore.entries.isEmpty {
                    searchField
                        .padding(.bottom, 16)
                }

                if historyStore.entries.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    noResults
                } else {
                    ForEach(grouped, id: \.title) { group in
                        Text(group.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .padding(.top, 6)
                            .padding(.bottom, 8)
                        VStack(spacing: 10) {
                            ForEach(group.entries) { entry in
                                row(for: entry)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .alert("Clear all history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear all", role: .destructive) { historyStore.clearAll() }
        } message: {
            Text("This permanently deletes all \(historyStore.entries.count) saved transcriptions and their audio. This can't be undone.")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.4))
            TextField("Search transcriptions", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Color.white.opacity(0.4))
            Text("No matches for “\(search)”")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
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
                        HStack(spacing: 6) {
                            if entry.failed {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.orange)
                            }
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        HStack(spacing: 10) {
                            if entry.failed {
                                metaText("Failed")
                            } else {
                                // Plain, readable: "43 words · 23s · Grammar"
                                metaText("\(entry.wordCount) words")
                            }
                            if entry.durationSeconds > 0 {
                                metaDot(); metaText(durationText(entry.durationSeconds))
                            }
                            if entry.wasCleaned {
                                metaDot(); metaText(cleanupLabel(entry))
                            }
                        }
                    }
                    Spacer()
                    rowActions(for: entry)
                }

                // Failed entry → muted error; otherwise the inserted text.
                if entry.failed {
                    Text(entry.errorMessage.isEmpty ? "No transcript was produced — re-transcribe to try again." : entry.errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.orange.opacity(0.7))
                } else {
                    Text(entry.finalText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .textSelection(.enabled)
                        .lineLimit(isExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)

                    // Expand/collapse when the text is long (or show the raw
                    // original once expanded, if cleanup changed it).
                    if entry.finalText.count > 140 || entry.wasCleaned {
                        Button(isExpanded ? "Show less" : (entry.wasCleaned ? "Show more · original" : "Show more")) {
                            if isExpanded { expandedIDs.remove(entry.id) } else { expandedIDs.insert(entry.id) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))

                        if isExpanded && entry.wasCleaned {
                            Text("Original: \(entry.rawText)")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .textSelection(.enabled)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
        .opacity(entry.failed ? 0.75 : 1)   // de-emphasize failures
    }

    private func rowActions(for entry: HistoryEntry) -> some View {
        HStack(spacing: 8) {
            if entry.hasAudio, let url = historyStore.audioURL(for: entry) {
                let playing = player.isPlaying(url)
                dsCardButton(icon: playing ? "pause.fill" : "play.fill",
                             label: playing ? "Pause" : "Play") {
                    player.toggle(url: url)
                }
                // Retry: re-transcribe the saved audio. For a failed entry this
                // fills it in place; for a good entry it copies the fresh text.
                if retryingID == entry.id {
                    HStack(spacing: 6) {
                        LoadingSpinner(size: 12, lineWidth: 1.8)
                        Text("Retrying")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                } else {
                    // "Retry" for a failed capture; "Re-transcribe" for a good one
                    // (re-running from audio, distinct from re-run-cleanup).
                    let label = retryNoticeID == entry.id ? "Done" : (entry.failed ? "Retry" : "Re-transcribe")
                    dsCardButton(icon: retryNoticeID == entry.id ? "checkmark" : "arrow.clockwise",
                                 label: label) {
                        retry(entry)
                    }
                }
            }
            if !entry.failed {
                dsCardButton(icon: copiedID == entry.id ? "checkmark" : "doc.on.doc",
                             label: copiedID == entry.id ? "Copied" : "Copy") {
                    copy(entry.finalText, id: entry.id)
                }
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

    /// Re-transcribe the saved audio. Failed entries are filled in place; for a
    /// successful entry, the fresh text is copied to the clipboard.
    private func retry(_ entry: HistoryEntry) {
        retryingID = entry.id
        appState.retryHistory(entry) { success, text in
            retryingID = nil
            guard success else { return }
            retryNoticeID = entry.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if retryNoticeID == entry.id { retryNoticeID = nil }
            }
            // For a successful (non-failed) entry, retry copies to clipboard.
            // Failed entries fill in place (no copy) so the row now shows text.
            if entry.failed == false, let text = text, !text.isEmpty {
                let pb = NSPasteboard.general
                pb.clearContents(); pb.setString(text, forType: .string)
            }
        }
    }

    /// Plain metadata text (e.g. "43 words"), dot-separated — clearer than the
    /// old icon-prefixed chips.
    private func metaText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.5))
    }

    private func metaDot() -> some View {
        Text("·")
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.3))
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
        .environmentObject(AppState())
        .frame(width: 700, height: 560)
        .background(Color.black)
}
