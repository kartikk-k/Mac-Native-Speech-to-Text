//
//  OverlayView.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

// MARK: - Spinner matching the SVG: circle track (0.3 opacity) + arc (white)

struct LoadingSpinner: View {
    let size: CGFloat
    let lineWidth: CGFloat
    @State private var rotation: Double = 0

    init(size: CGFloat = 16, lineWidth: CGFloat = 2.3) {
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Overlay

struct OverlayView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        let monitor = appState.audioLevelMonitor
        WaveformContent(appState: appState, monitor: monitor)
    }
}

/// Inner view that observes the AudioLevelMonitor for real-time updates.
private struct WaveformContent: View {
    @ObservedObject var appState: AppState
    @ObservedObject var monitor: AudioLevelMonitor

    var body: some View {
        HStack(spacing: 10) {
            // Cancel button
            Button(action: {
                appState.cancelListening()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)

            // Center content
            if appState.phase == .listening {
                // Waveform bars driven by real audio levels
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 2, height: barHeight(for: i))
                            .animation(.easeOut(duration: 0.08), value: monitor.levels[i])
                    }
                }
                .frame(height: 22)

                // Stop button
                Button(action: {
                    appState.stopListening()
                }) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)

            } else if appState.phase == .processing {
                LoadingSpinner(size: 14, lineWidth: 2)
                    .padding(.trailing, 4)
                    .opacity(0.6)
            } else if appState.phase == .permissionDenied {
                Button(action: {
                    appState.onShowOnboarding?()
                    appState.phase = .hidden
                    appState.onHide?()
                }) {
                    Text("Permissions required")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.trailing, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: appState.phase)
        .frame(maxWidth: .infinity)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 4
        let maxHeight: CGFloat = 20
        let level = monitor.levels[index]
        return base + (maxHeight - base) * level
    }
}

// MARK: - Previews

private class PreviewAppState: AppState {
    init(phase: RecognitionPhase) {
        super.init()
        self.phase = phase
    }
}

#Preview("Listening") {
    OverlayView()
        .environmentObject(PreviewAppState(phase: .listening) as AppState)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Processing") {
    OverlayView()
        .environmentObject(PreviewAppState(phase: .processing) as AppState)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Spinner Only") {
    LoadingSpinner(size: 24, lineWidth: 2.5)
        .padding(40)
        .background(Color.black)
}

#Preview("Permission") {
    OverlayView()
        .environmentObject(PreviewAppState(phase: .permissionDenied) as AppState)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
