//
//  SilenceTrimmer.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Removes long "thinking" pauses from a recording before it's sent for
//  transcription. People pause to think mid-sentence; those multi-second gaps of
//  near-silence add latency and cost without adding words.
//
//  DESIGN PRINCIPLE: never drop speech, even quiet/whispered speech. It is far
//  better to leave a pause in than to clip a word. So the trimmer is deliberately
//  conservative:
//    * The silence threshold is derived from THIS recording's own dynamic range
//      (relative to its loudest speech), not a fixed absolute level — a whisper
//      recorded quietly still sits well above its own background and is kept.
//    * We only collapse a silence run when it's clearly long (default > 0.8s) AND
//      clearly below the speech level; we always leave a short natural gap.
//    * A hard safety valve: if trimming would remove more than `maxTrimFraction`
//      of the audio, we assume the threshold misfired and return the ORIGINAL
//      audio untouched. This guarantees we can never silently eat half the words.
//
//  Operates on mono signed-16-bit little-endian PCM ("pcm16").
//

import Foundation

enum SilenceTrimmer {

    /// Trim pauses longer than `maxPauseSeconds` down to `keptPauseSeconds`.
    /// Conservative by design — see file header. Returns the input unchanged if
    /// it's too short to frame or if trimming would remove too much.
    static func trim(pcm16: Data,
                     sampleRate: Int,
                     maxPauseSeconds: Double = 0.8,
                     keptPauseSeconds: Double = 0.2,
                     maxTrimFraction: Double = 0.6) -> Data {
        guard sampleRate > 0, pcm16.count >= MemoryLayout<Int16>.size else { return pcm16 }

        let sampleCount = pcm16.count / MemoryLayout<Int16>.size
        let frameSize = max(1, sampleRate / 50)          // ~20 ms frames
        let frameCount = sampleCount / frameSize
        guard frameCount > 4 else { return pcm16 }

        // Per-frame RMS.
        var frameRMS = [Double](repeating: 0, count: frameCount)
        pcm16.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for f in 0..<frameCount {
                let base = f * frameSize
                var sumSquares = 0.0
                for i in 0..<frameSize {
                    let sample = raw.loadUnaligned(fromByteOffset: (base + i) * 2, as: Int16.self)
                    let v = Double(sample)
                    sumSquares += v * v
                }
                frameRMS[f] = (sumSquares / Double(frameSize)).squareRoot()
            }
        }

        let sorted = frameRMS.sorted()
        // Noise floor: low percentile of frame energies (the quietest ~10%).
        let floor = sorted[max(0, Int(Double(sorted.count) * 0.10))]
        // Speech level: near the top (95th percentile) so it reflects the loudest
        // real speech even when most of the recording is silence — this keeps
        // leading/trailing-silence recordings trimmable. Robust to a stray spike
        // by not using the absolute max.
        let speechLevel = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]

        // If there's essentially no dynamic range (uniform hiss, dead silence, or
        // a perfectly flat signal), there's nothing safe to trim — leave it alone.
        guard speechLevel > floor * 2.5, speechLevel > 1.0 else { return pcm16 }

        // Anchor the threshold to the NOISE FLOOR, not the speech level. Silence
        // is "a bit above the floor"; anything meaningfully louder — including a
        // quiet whisper that still sits well above the room's background — counts
        // as voiced. We also cap the threshold so it can never climb close to the
        // speech level (which would start eating quiet speech).
        //   threshold = max(floor * 2.2, floor + 40),  capped at 35% toward speech.
        let floorAnchored = max(floor * 2.2, floor + 40.0)
        let cap = floor + (speechLevel - floor) * 0.35
        let threshold = min(floorAnchored, cap)
        let voiced = frameRMS.map { $0 >= threshold }

        let maxPauseFrames = max(1, Int((maxPauseSeconds * Double(sampleRate)) / Double(frameSize)))
        let keptPauseFrames = max(1, Int((keptPauseSeconds * Double(sampleRate)) / Double(frameSize)))

        var output = Data(capacity: pcm16.count)
        var f = 0
        while f < frameCount {
            if voiced[f] {
                appendFrames(from: pcm16, frame: f, count: 1, frameSize: frameSize, into: &output)
                f += 1
                continue
            }
            var runEnd = f
            while runEnd < frameCount && !voiced[runEnd] { runEnd += 1 }
            let runLength = runEnd - f

            if runLength > maxPauseFrames {
                let isEdge = (f == 0) || (runEnd == frameCount)
                let keep = isEdge ? keptPauseFrames / 2 : keptPauseFrames  // trim, but keep a little
                appendFrames(from: pcm16, frame: f, count: min(keep, runLength), frameSize: frameSize, into: &output)
            } else {
                appendFrames(from: pcm16, frame: f, count: runLength, frameSize: frameSize, into: &output)
            }
            f = runEnd
        }

        // Preserve any trailing partial frame (< 20 ms) that framing dropped.
        let framedBytes = frameCount * frameSize * MemoryLayout<Int16>.size
        if framedBytes < pcm16.count {
            output.append(pcm16.subdata(in: framedBytes..<pcm16.count))
        }

        // Safety valve: if we somehow removed too much, the classifier misfired —
        // send the original rather than risk dropping speech.
        let removedFraction = 1.0 - (Double(output.count) / Double(pcm16.count))
        if output.isEmpty || removedFraction > maxTrimFraction {
            return pcm16
        }
        return output
    }

    private static func appendFrames(from pcm16: Data,
                                     frame: Int,
                                     count: Int,
                                     frameSize: Int,
                                     into output: inout Data) {
        guard count > 0 else { return }
        let start = frame * frameSize * MemoryLayout<Int16>.size
        let length = count * frameSize * MemoryLayout<Int16>.size
        let end = min(pcm16.count, start + length)
        guard start < end else { return }
        output.append(pcm16.subdata(in: start..<end))
    }
}
