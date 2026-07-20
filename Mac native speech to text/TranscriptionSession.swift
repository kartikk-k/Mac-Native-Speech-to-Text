//
//  TranscriptionSession.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Foundation

/// A single record + transcribe session, independent of the engine behind it.
///
/// Implemented by `SpeechSession` (Apple's built-in recognizer) and
/// `GPTRealtimeSession` (OpenAI Realtime transcription). Callers interact with
/// both through this protocol so switching engines is a one-line change.
///
/// Both implementations call the `onResult(text, isFinal)` closure supplied at
/// construction: repeatedly with `isFinal == false` for interim text, and once
/// with `isFinal == true` for the final transcript.
protocol TranscriptionSession: AnyObject {
    var isRecording: Bool { get }
    func startRecording()
    func stopAndTranscribe()
    func cancel()
}
