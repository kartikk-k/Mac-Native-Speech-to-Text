//
//  AudioLevelMonitor.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/9/26.
//

import Foundation
import AVFoundation
import Accelerate
import Combine

/// Publishes real-time audio levels from the microphone for waveform visualization.
final class AudioLevelMonitor: ObservableObject {
    /// Smoothed bar levels (0...1), one per waveform bar.
    @Published var levels: [CGFloat] = Array(repeating: 0, count: 7)

    /// Raw RMS level (0...1).
    private var currentRMS: Float = 0
    private var history: [Float] = []
    private let historySize = 7

    /// Call from the audio tap buffer to update levels.
    func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        // Calculate RMS
        var rms: Float = 0
        vDSP_measqv(channelData, 1, &rms, vDSP_Length(count))
        rms = sqrtf(rms)

        // Convert to 0...1 range with some scaling for better visual response
        // Typical speech RMS is ~0.01-0.1, so we scale up
        let normalized = min(rms * 50.0, 1.0)

        // Maintain a rolling history for the bars
        history.append(normalized)
        if history.count > historySize {
            history.removeFirst()
        }

        // Pad history to always have 7 entries
        let padded: [Float]
        if history.count < historySize {
            padded = Array(repeating: Float(0), count: historySize - history.count) + history
        } else {
            padded = Array(history)
        }

        // Spread the history across bars with some variation
        // Center bar gets latest, outer bars get older values
        let barOrder = [3, 2, 4, 1, 5, 0, 6] // center-out ordering
        var newLevels = Array(repeating: CGFloat(0), count: 7)
        for (i, barIndex) in barOrder.enumerated() {
            let idx = min(i, padded.count - 1)
            newLevels[barIndex] = CGFloat(padded[padded.count - 1 - idx])
        }

        DispatchQueue.main.async { [newLevels] in
            // Smooth transition
            for i in 0..<7 {
                self.levels[i] = self.levels[i] * 0.3 + newLevels[i] * 0.7
            }
        }
    }

    func reset() {
        history.removeAll()
        DispatchQueue.main.async {
            self.levels = Array(repeating: 0, count: 7)
        }
    }
}
