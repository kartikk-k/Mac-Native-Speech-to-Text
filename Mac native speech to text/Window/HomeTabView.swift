//
//  HomeTabView.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

struct HomeTabView: View {
    @Environment(UsageTracker.self) private var usage

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                Text("Welcome back")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)

                // Quick stats
                dsCard {
                    HStack(spacing: 0) {
                        statItem(value: dsFormattedCount(usage.totalWords), label: "Total words")
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 36)
                        statItem(value: "\(Int(usage.averageWordsPerMinute))", label: "WPM")
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 36)
                        statItem(value: dsFormattedStreak(usage.currentStreak), label: "Streak")
                            .frame(maxWidth: .infinity)
                    }
                }

                dsSectionHeader(icon: "calendar", title: "Today")

                if usage.todaySessions == 0 {
                    dsCard {
                        HStack(spacing: 12) {
                            Image(systemName: "mic.slash")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.white.opacity(0.40))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No dictations yet")
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(.white)
                                Text("Hold \(Image(systemName: "globe")) (Fn) anywhere to start dictating.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.40))
                            }
                            Spacer()
                        }
                    }
                } else {
                    dsCard {
                        HStack(spacing: 24) {
                            statItem(value: dsFormattedCount(usage.todayWords), label: "words")
                                .frame(maxWidth: .infinity)
                            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 36)
                            statItem(value: "\(usage.todaySessions)", label: "sessions")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                dsSectionHeader(icon: "keyboard", title: "How to use")

                dsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        instructionRow(step: "1", text: Text("Hold \(Image(systemName: "globe")) (Fn) to start recording"))
                        dsDivider()
                        instructionRow(step: "2", text: Text("Speak naturally — release to transcribe and insert"))
                        dsDivider()
                        instructionRow(step: "3", text: Text("Press \(Image(systemName: "globe")) + Space for hands-free mode"))
                    }
                }

//                dsSectionHeader(icon: "link", title: "Links")
//
//                dsCard {
//                    HStack(spacing: 10) {
//                        dsCardButton(icon: "arrow.up.right.square", label: "View on GitHub") {
//                            if let url = URL(string: "https://github.com/kartikk-k/Mac-Native-Speech-to-Text") {
//                                NSWorkspace.shared.open(url)
//                            }
//                        }
//                    }
//                }

                // Footer
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.25))
                        Text("Echotype Mac - v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.30))
                    }
                    Text("Open-source, on-device speech recognition for macOS.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.20))
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.40))
        }
    }

    private func instructionRow(step: String, text: Text) -> some View {
        HStack(spacing: 12) {
            Text(step)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.15))
                )
            text
                .font(.system(size: 13.5))
                .foregroundStyle(.white)
        }
    }
}

#Preview("Home") {
    HomeTabView()
        .environment(UsageTracker())
        .frame(width: 600, height: 500)
}
