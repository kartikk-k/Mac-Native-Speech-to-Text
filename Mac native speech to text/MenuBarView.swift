//
//  MenuBarView.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if appState.isListening {
                Text("Listening...")
                    .font(.headline)
            } else if !appState.lastTranscription.isEmpty {
                Text("Last transcription:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(appState.lastTranscription)
                    .font(.body)
                    .lineLimit(3)
            } else {
                Text("Hold ⌃⌥ (Ctrl+Option) to dictate")
                    .font(.body)
            }
        }
        .padding(8)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
