//
//  AudioEnhancer.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Real-time speech enhancement applied to mic audio BEFORE it's sent for
//  transcription. Quiet, whispered, or slow speech was transcribing poorly
//  because it reached the model too soft. This brings such speech up to a
//  consistent, clearly-audible level and quiets the background between words —
//  the same thing other dictation apps do.
//
//  Two stages on 24 kHz mono signed-16-bit PCM, in place:
//    1. AGC (automatic gain control) — track the loud (speech) envelope and apply
//       a smoothed gain that pulls it toward a target level. Quiet speech is
//       boosted; gain is capped and a limiter prevents clipping.
//    2. Noise gate — track a slow noise floor (minimum-follower); frames near the
//       floor are attenuated (not muted) so background hiss between words is
//       quieted without eating soft word onsets.
//
//  Stateful/streaming: one instance per recording; feed chunks in capture order;
//  reset() between recordings.
//

import Foundation

final class AudioEnhancer {

    // MARK: Tunables (balanced)

    /// Target level for speech, as a fraction of full scale (Int16 max = 32767).
    private let targetLevel: Float = 0.20 * 32767
    private let maxGain: Float = 10.0
    private let minGain: Float = 1.0
    /// Gain smoothing per frame (attack rises faster than release for clarity,
    /// but both are slow enough to avoid audible pumping).
    private let gainAttack: Float = 0.30
    private let gainRelease: Float = 0.05

    /// A frame counts as speech (drives AGC) when its level clears both an
    /// absolute minimum and a margin above the tracked noise floor.
    private let speechAbsMin: Float = 300
    private let speechFloorMargin: Float = 2.5

    /// Noise gate: frames below `floor * gateThreshold` are attenuated toward
    /// `gateFloorGain` (never fully muted).
    private let gateThreshold: Float = 1.8
    private let gateFloorGain: Float = 0.5

    /// ~20 ms frames at 24 kHz.
    private let frameSize = 480

    // MARK: State

    private var currentGain: Float = 1.0
    /// Envelope of recent speech level, used as the AGC reference.
    private var speechEnvelope: Float = 0
    /// Slow minimum-follower estimate of the background noise level.
    private var noiseFloor: Float = 150
    private var seenSpeech = false

    func reset() {
        currentGain = 1.0
        speechEnvelope = 0
        noiseFloor = 150
        seenSpeech = false
    }

    func process(_ pcm: Data) -> Data {
        guard pcm.count >= MemoryLayout<Int16>.size else { return pcm }
        var samples = [Int16](repeating: 0, count: pcm.count / MemoryLayout<Int16>.size)
        _ = samples.withUnsafeMutableBytes { pcm.copyBytes(to: $0) }

        let n = samples.count
        var i = 0
        while i < n {
            let end = min(i + frameSize, n)
            let count = end - i

            var sumSq: Float = 0
            for j in i..<end { let v = Float(samples[j]); sumSq += v * v }
            let rms = (sumSq / Float(count)).squareRoot()

            // Noise floor: minimum-follower. Drop quickly toward quieter frames,
            // rise very slowly — so it settles at the true background, not speech.
            if rms < noiseFloor {
                noiseFloor = noiseFloor * 0.85 + rms * 0.15
            } else {
                noiseFloor = noiseFloor * 0.999 + rms * 0.001
            }
            noiseFloor = max(40, noiseFloor)

            let isSpeech = rms > speechAbsMin && rms > noiseFloor * speechFloorMargin

            if isSpeech {
                // Track the speech envelope and steer gain toward the target.
                speechEnvelope = seenSpeech ? (speechEnvelope * 0.8 + rms * 0.2) : rms
                seenSpeech = true
                let desired = min(maxGain, max(minGain, targetLevel / max(speechEnvelope, 1)))
                let rate = desired > currentGain ? gainAttack : gainRelease
                currentGain += (desired - currentGain) * rate
            }
            // During non-speech, hold the gain (don't crank it up on silence).

            // Gate: attenuate frames close to the noise floor.
            let gateGain: Float = rms < noiseFloor * gateThreshold ? gateFloorGain : 1.0
            let g = currentGain * gateGain

            for j in i..<end {
                let boosted = Float(samples[j]) * g
                samples[j] = Int16(min(32767, max(-32768, boosted)))
            }
            i = end
        }

        return samples.withUnsafeBytes { Data($0) }
    }
}
