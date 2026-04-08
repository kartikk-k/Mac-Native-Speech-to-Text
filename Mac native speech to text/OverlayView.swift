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
    @State private var dotPhase: CGFloat = 0

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
                // Waveform bars
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 2, height: dotHeight(for: i))
                            .animation(
                                .easeInOut(duration: 0.4)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.08),
                                value: dotPhase
                            )
                    }
                }
                .frame(height: 16)

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
        .onAppear {
            dotPhase = 1
        }
        .onChange(of: appState.phase) { _, newPhase in
            if newPhase == .listening {
                dotPhase = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    dotPhase = 1
                }
            }
        }
    }

    private func dotHeight(for index: Int) -> CGFloat {
        guard appState.phase == .listening else { return 3 }
        let base: CGFloat = 4
        let amplitude: CGFloat = 10
        let offsets: [CGFloat] = [0.3, 0.7, 1.0, 0.8, 1.0, 0.6, 0.4]
        return base + amplitude * offsets[index] * dotPhase
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
