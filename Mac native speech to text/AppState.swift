//
//  AppState.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Foundation
import Combine
import AppKit

enum RecognitionPhase {
    case hidden
    case listening
    case processing
    case permissionDenied
}

class AppState: ObservableObject {
    @Published var phase: RecognitionPhase = .hidden
    @Published var transcribedText = ""

    private let speechManager = SpeechManager()
    private var currentSession: SpeechSession?

    var onHide: (() -> Void)?
    var onShowOnboarding: (() -> Void)?
    var permissionManager: PermissionManager?

    func startListening() {
        if let pm = permissionManager, !pm.allPermissionsGranted {
            phase = .permissionDenied
            return
        }

        if let old = currentSession {
            if old.isRecording { old.cancel() }
        }

        print("[AppState] === START ===")
        phase = .listening
        transcribedText = ""

        let session = speechManager.createSession { [weak self] text, isFinal in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if !isFinal {
                    if self.phase == .processing {
                        self.transcribedText = text
                    }
                } else {
                    print("[AppState] final: \"\(text)\"")
                    if !text.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            TextInserter.insert(text)
                            print("[AppState] inserted")
                        }
                    }
                    self.phase = .hidden
                    self.onHide?()
                }
            }
        }

        guard let session = session else {
            phase = .hidden
            return
        }

        currentSession = session
        session.startRecording()
    }

    func stopListening() {
        guard phase == .listening, let session = currentSession else { return }
        print("[AppState] === STOP → PROCESSING ===")
        phase = .processing
        session.stopAndTranscribe()

        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self, self.phase == .processing else { return }
            let text = self.transcribedText
            if !text.isEmpty {
                TextInserter.insert(text)
            }
            self.phase = .hidden
            self.onHide?()
        }
    }

    func cancelListening() {
        print("[AppState] === CANCEL ===")
        currentSession?.cancel()
        currentSession = nil
        phase = .hidden
        transcribedText = ""
        onHide?()
    }
}
