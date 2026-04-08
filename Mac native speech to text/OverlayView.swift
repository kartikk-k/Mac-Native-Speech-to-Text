//
//  OverlayView.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Pulsing ring when listening
                if appState.isListening {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                        .frame(width: 44, height: 44)
                        .scaleEffect(appState.isListening ? 1.4 : 1.0)
                        .opacity(appState.isListening ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: appState.isListening
                        )
                }

                Circle()
                    .fill(appState.isListening ? Color.blue : Color.green)
                    .frame(width: 36, height: 36)

                Image(systemName: appState.isListening ? "mic.fill" : "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private var statusText: String {
        if appState.isListening {
            return appState.transcribedText.isEmpty
                ? "Listening..."
                : appState.transcribedText
        } else {
            return appState.lastTranscription.isEmpty
                ? "Done"
                : "Copied!"
        }
    }
}
