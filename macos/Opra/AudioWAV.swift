//
//  AudioWAV.swift
//  Opra
//
//  Encodes mono Float PCM samples (what KokoroSwift's generateAudio returns) into a
//  16-bit PCM WAV container that AVAudioPlayer(data:) can play.
//

import Foundation

enum AudioWAV {
    static func data(fromMonoFloat samples: [Float], sampleRate: Int) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample
        let dataSize = samples.count * bytesPerSample

        var data = Data(capacity: 44 + dataSize)
        func appendString(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func appendU32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func appendU16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }

        appendString("RIFF")
        appendU32(UInt32(36 + dataSize))
        appendString("WAVE")
        appendString("fmt ")
        appendU32(16)                 // fmt chunk size (PCM)
        appendU16(1)                  // audio format = PCM
        appendU16(UInt16(channels))
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(byteRate))
        appendU16(UInt16(blockAlign))
        appendU16(UInt16(bitsPerSample))
        appendString("data")
        appendU32(UInt32(dataSize))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var le = Int16(clamped * 32767.0).littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }
}
