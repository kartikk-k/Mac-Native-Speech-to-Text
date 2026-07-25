//
//  HomeTabView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  The single dashboard: current status, how-to for new users, and usage stats.
//  (The former separate Stats tab was merged in here.)
//

import SwiftUI

struct HomeTabView: View {
    @Environment(UsageTracker.self) private var usage
    @Environment(PermissionManager.self) private var permissions
    @EnvironmentObject private var appState: AppState

    // Show the "How to use" block expanded until the user has dictated at least
    // once; after that it collapses (they can reopen it).
    @State private var howToExpanded = true

    private var isNewUser: Bool { usage.totalSessions == 0 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // Header + live status chip.
                HStack(alignment: .center) {
                    Text("Welcome back")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    statusChip
                }
                .padding(.bottom, 20)

                // For a new user, put "How to use" FIRST — it's the most useful.
                if isNewUser || howToExpanded {
                    howToUse
                        .padding(.bottom, 20)
                }

                // Quick stats.
                dsCard {
                    HStack(spacing: 0) {
                        statItem(value: dsFormattedCount(usage.totalWords), label: "Total words")
                            .frame(maxWidth: .infinity)
                        divider
                        statItem(value: "\(usage.wordsPerMinute)", label: "Avg WPM")
                            .frame(maxWidth: .infinity)
                        // Streak is only motivating once it's a real streak.
                        if usage.currentStreak >= 2 {
                            divider
                            statItem(value: dsFormattedStreak(usage.currentStreak), label: "Streak")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.bottom, 4)

                dsSectionHeader(icon: "calendar", title: "Today")

                if usage.todaySessions == 0 {
                    dsCard {
                        HStack(spacing: 12) {
                            Image(systemName: "mic.slash")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No dictations yet")
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(.white)
                                HStack(spacing: 4) {
                                    Text("Hold")
                                    keycap("Fn")
                                    Text("anywhere to start dictating.")
                                }
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.white.opacity(0.55))
                            }
                            Spacer()
                        }
                    }
                } else {
                    dsCard {
                        HStack(spacing: 0) {
                            statItem(value: dsFormattedCount(usage.todayWords), label: "words today")
                                .frame(maxWidth: .infinity)
                            divider
                            statItem(value: "\(usage.todaySessions)", label: "sessions today")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                // All-time detail (folded in from the old Stats tab).
                dsSectionHeader(icon: "chart.bar", title: "All time")
                dsCard {
                    HStack(spacing: 0) {
                        statItem(value: "\(usage.totalSessions)", label: "sessions")
                            .frame(maxWidth: .infinity)
                        divider
                        statItem(value: dsFormattedCount(usage.totalCharacters), label: "characters")
                            .frame(maxWidth: .infinity)
                        divider
                        statItem(value: dsFormattedTime(usage.totalRecordingSeconds), label: "recorded")
                            .frame(maxWidth: .infinity)
                    }
                }

                // Returning users get "How to use" as a collapsible at the bottom.
                if !isNewUser {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { howToExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 11, weight: .medium))
                            Text("How to use")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: howToExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                }

                footer
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Status chip

    private var statusChip: some View {
        let (dot, text): (Color, String) = {
            if !permissions.microphoneGranted { return (.orange, "Mic permission needed") }
            if !permissions.accessibilityGranted { return (.orange, "Accessibility needed") }
            switch appState.phase {
            case .listening: return (.green, "Listening")
            case .processing: return (.yellow, "Transcribing")
            case .cleaning: return (.yellow, "Improving")
            default: return (.green, "Ready")
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    // MARK: - How to use

    private var howToUse: some View {
        dsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Text("How to use")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .padding(.bottom, 2)
                instructionRow(step: "1") {
                    HStack(spacing: 4) { Text("Hold"); keycap("Fn"); Text("to start recording") }
                }
                dsDivider()
                instructionRow(step: "2") { Text("Speak naturally — release to transcribe and insert") }
                dsDivider()
                instructionRow(step: "3") {
                    HStack(spacing: 4) { Text("Double-press"); keycap("Fn"); Text("for hands-free — or press"); keycap("Space"); Text("while holding") }
                }
                dsDivider()
                instructionRow(step: "4") {
                    HStack(spacing: 4) { Text("In hands-free, press"); keycap("Fn"); Text("once to stop") }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.30))
                Text("Echotype Mac — v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.40))
            }
            Text("Open-source, on-device speech recognition for macOS.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.30))
        }
        .padding(.top, 28)
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 36)
    }

    /// A small key-cap styled badge, e.g. Fn / Space, so shortcuts read as keys.
    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private func instructionRow<Content: View>(step: String, @ViewBuilder text: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(step)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.15)))
            text()
                .font(.system(size: 13.5))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }
}

#Preview("Home") {
    HomeTabView()
        .environment(UsageTracker())
        .environment(PermissionManager())
        .environmentObject(AppState())
        .frame(width: 640, height: 640)
}
