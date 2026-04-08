//
//  OverlayView.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)

            // Waveform dots
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 3, height: dotHeight(for: i))
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
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .padding(5)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            dotPhase = 1
        }
        .onChange(of: appState.isListening) { _, newValue in
            dotPhase = newValue ? 1 : 0
        }
    }

    private func dotHeight(for index: Int) -> CGFloat {
        guard appState.isListening else { return 3 }
        let base: CGFloat = 4
        let amplitude: CGFloat = 10
        // Staggered heights for wave effect
        let offsets: [CGFloat] = [0.3, 0.7, 1.0, 0.8, 1.0, 0.6, 0.4]
        return base + amplitude * offsets[index] * dotPhase
    }
}
