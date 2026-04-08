//
//  AppState.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Foundation
import Combine
import AppKit

class AppState: ObservableObject {
    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var lastTranscription = ""

    private var speechManager: SpeechManager?

    init() {
        speechManager = SpeechManager { [weak self] text, isFinal in
            DispatchQueue.main.async {
                self?.transcribedText = text
                if isFinal {
                    self?.lastTranscription = text
                    self?.copyToClipboard(text)
                }
            }
        }
    }

    func startListening() {
        guard !isListening else { return }
        isListening = true
        transcribedText = ""
        speechManager?.startRecognition()
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        speechManager?.stopRecognition()
    }

    private func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
