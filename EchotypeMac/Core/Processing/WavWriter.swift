//
//  WavWriter.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Wraps raw little-endian PCM16 samples in a minimal WAV container so failed
//  GPT captures can be saved to disk and re-uploaded to OpenAI on retry.
//

import Foundation

enum WavWriter {
    /// Write mono/stereo PCM16 data to a `.wav` file at `url`.
    static func write(pcm16 data: Data, sampleRate: Int, channels: Int, to url: URL) throws {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = data.count
        let chunkSize = 36 + dataSize

        var header = Data()
        func appendString(_ s: String) { header.append(s.data(using: .ascii)!) }
        func appendUInt32LE(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { header.append(contentsOf: $0) }
        }
        func appendUInt16LE(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { header.append(contentsOf: $0) }
        }

        appendString("RIFF")
        appendUInt32LE(UInt32(chunkSize))
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32LE(16)                         // PCM fmt chunk size
        appendUInt16LE(1)                          // audio format = PCM
        appendUInt16LE(UInt16(channels))
        appendUInt32LE(UInt32(sampleRate))
        appendUInt32LE(UInt32(byteRate))
        appendUInt16LE(UInt16(blockAlign))
        appendUInt16LE(UInt16(bitsPerSample))
        appendString("data")
        appendUInt32LE(UInt32(dataSize))

        var file = header
        file.append(data)
        try file.write(to: url, options: .atomic)
    }
}
