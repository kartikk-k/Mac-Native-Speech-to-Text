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
                print("[AppState] received text: \"\(text)\" (final: \(isFinal))")
                self?.transcribedText = text
                if isFinal {
                    self?.lastTranscription = text
                }
            }
        }
    }

    func startListening() {
        guard !isListening else {
            print("[AppState] startListening called but already listening")
            return
        }
        print("[AppState] === START LISTENING ===")
        isListening = true
        transcribedText = ""
        lastTranscription = ""
        speechManager?.startRecognition()
    }

    func stopListening() {
        guard isListening else {
            print("[AppState] stopListening called but not listening")
            return
        }
        print("[AppState] === STOP LISTENING ===")
        isListening = false
        speechManager?.stopRecognition()

        // Grab whatever text we have right now and insert it
        let textToInsert = transcribedText
        print("[AppState] text to insert: \"\(textToInsert)\"")

        guard !textToInsert.isEmpty else {
            print("[AppState] nothing to insert")
            return
        }
        lastTranscription = textToInsert

        // Small delay to let modifier keys fully release before typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            print("[AppState] calling TextInserter.insert now")
            TextInserter.insert(textToInsert)
            print("[AppState] TextInserter.insert completed")
        }
    }

    func cancelListening() {
        guard isListening else { return }
        print("[AppState] === CANCEL LISTENING ===")
        isListening = false
        transcribedText = ""
        speechManager?.stopRecognition()
    }
}
