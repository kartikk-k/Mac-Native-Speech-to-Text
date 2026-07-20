//
//  RetryTabView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Lists captures whose transcription failed. The audio is kept on-device so
//  the user can re-run it whenever they like (e.g. after a network hiccup or an
//  OpenAI outage), or play it back / delete it.
//

import SwiftUI
import AVFoundation
import AppKit

struct RetryTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var failedStore: FailedTranscriptionStore

    @State private var retryingIDs: Set<UUID> = []
    @State private var resultMessages: [UUID: String] = [:]
    @State private var copiedNotice: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Failed Captures")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 4)

                Text("Recordings that couldn't be transcribed are saved here. Retry them any time — nothing is lost.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.bottom, 20)

                if let notice = copiedNotice {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green.opacity(0.85))
                        Text(notice)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.green.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.green.opacity(0.25), lineWidth: 1)
                            )
                    )
                    .padding(.bottom, 12)
                }

                if failedStore.items.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(failedStore.items) { item in
                            row(for: item)
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
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34))
                .foregroundStyle(Color.green.opacity(0.7))
            Text("No failed captures")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
            Text("Everything has been transcribed successfully.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func row(for item: FailedTranscription) -> some View {
        let isFocused = appState.pendingFailedFocusID == item.id
        let isRetrying = retryingIDs.contains(item.id)

        return dsCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.85))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.white)
                    Text("\(item.providerDisplayName) · \(item.model)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                    if let message = resultMessages[item.id] {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange.opacity(0.8))
                    } else {
                        Text(item.errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    dsCardButton(icon: "play.fill", label: "Play") {
                        AudioPreviewPlayer.shared.play(url: failedStore.audioURL(for: item))
                    }

                    if isRetrying {
                        HStack(spacing: 6) {
                            LoadingSpinner(size: 12, lineWidth: 1.8)
                            Text("Retrying")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    } else {
                        dsCardButton(icon: "arrow.clockwise", label: "Retry") {
                            retry(item)
                        }
                    }

                    Button {
                        failedStore.remove(item)
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
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isFocused ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }

    private func retry(_ item: FailedTranscription) {
        retryingIDs.insert(item.id)
        resultMessages[item.id] = nil
        // In-app retries copy the result to the clipboard rather than typing it,
        // since this window — not the user's target app — has focus.
        appState.retry(item: item, store: failedStore, insertOnSuccess: false) { success, text in
            retryingIDs.remove(item.id)
            if success {
                if let text = text, !text.isEmpty {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    let preview = text.count > 80 ? String(text.prefix(80)) + "…" : text
                    copiedNotice = "Transcribed & copied to clipboard: \"\(preview)\""
                } else {
                    copiedNotice = "Transcribed successfully (no speech detected)."
                }
                // The item is removed from the store on success; the row disappears.
            } else {
                resultMessages[item.id] = "Retry failed — check your connection or API key."
            }
        }
    }
}

/// Small shared player for previewing failed recordings.
final class AudioPreviewPlayer {
    static let shared = AudioPreviewPlayer()
    private var player: AVAudioPlayer?

    func play(url: URL) {
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

#Preview("Retry") {
    RetryTabView()
        .environmentObject(AppState())
        .environmentObject(FailedTranscriptionStore())
        .frame(width: 600, height: 500)
}
