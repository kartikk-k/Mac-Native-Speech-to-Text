//
//  StatsTabView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

struct StatsTabView: View {
    @Environment(UsageTracker.self) private var tracker

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                Text("Stats")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)

                // All time
                dsCard {
                    HStack(spacing: 24) {
                        statCell(icon: "waveform.path", value: dsFormattedCount(tracker.totalWords), label: "Total Words")
                        dsVerticalDivider()
                        statCell(icon: "mic.fill", value: "\(tracker.totalSessions)", label: "Sessions")
                        dsVerticalDivider()
                        statCell(icon: "gauge.with.needle", value: String(format: "%.0f", tracker.averageWordsPerMinute), label: "Avg WPM")
                    }
                }

                dsSectionHeader(icon: "chart.bar.fill", title: "Details")

                dsCard {
                    statRow(icon: "character.cursor.ibeam", title: "Total Characters", value: dsFormattedCount(tracker.totalCharacters))
                    dsDivider()
                    statRow(icon: "clock", title: "Recording Time", value: dsFormattedTime(tracker.totalRecordingSeconds))
                    dsDivider()
                    statRow(icon: "flame", title: "Day Streak", value: "\(tracker.currentStreak)")
                }

                dsSectionHeader(icon: "calendar", title: "Today")

                dsCard {
                    statRow(icon: "waveform.path", title: "Words", value: dsFormattedCount(tracker.todayWords))
                    dsDivider()
                    statRow(icon: "mic.fill", title: "Sessions", value: "\(tracker.todaySessions)")
                }

                Text("Stats are stored locally and reset each day for \"Today\" counters.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.20))
                    .padding(.top, 28)
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }

    private func statCell(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
            HStack(alignment: .center, spacing: 2){
//                Image(systemName: icon)
//                    .font(.system(size: 13, weight: .medium))
//                    .foregroundStyle(Color.white.opacity(0.6))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.40))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func statRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .monospacedDigit()
        }
    }
}

#Preview("Stats") {
    StatsTabView()
        .environment(UsageTracker())
        .frame(width: 600, height: 500)
}
