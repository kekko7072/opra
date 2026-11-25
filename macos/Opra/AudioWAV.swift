//
//  AudioWAV.swift
//  Opra
//
//  Encodes mono Float PCM samples (what KokoroSwift's generateAudio returns) into a
//  16-bit PCM WAV container that AVAudioPlayer(data:) can play.
//

import Foundation

private struct AudioWAVError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum AudioWAV {
    static func data(fromMonoFloat samples: [Float], sampleRate: Int) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var le = Int16(clamped * 32767.0).littleEndian
            withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
        }
        return data(fromMonoInt16PCM: pcm, sampleRate: sampleRate)
    }

    /// Input is signed 16-bit little-endian mono PCM.
    static func data(fromMonoInt16PCM pcm: Data, sampleRate: Int) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample
        let dataSize = pcm.count

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

        data.append(pcm)
        return data
    }
}

/// Incrementally writes the finite 24 kHz mono PCM WAV returned by local engines.
/// Only one generated chunk is held in memory, even for book-length exports.
final class PCM16WAVFileWriter {
    private let url: URL
    private let handle: FileHandle
    private var pcmByteCount: UInt32 = 0
    private var finished = false

    init(url: URL) throws {
        self.url = url
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: AudioWAV.data(fromMonoInt16PCM: Data(), sampleRate: 24_000))
    }

    func append(wav data: Data) throws {
        guard data.count >= 44,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            throw AudioWAVError(message: "A local voice returned invalid WAV audio.")
        }
        let pcm = data.dropFirst(44)
        guard pcm.count <= Int(UInt32.max - pcmByteCount) else {
            throw AudioWAVError(message: "The WAV export is larger than 4 GB. Export a smaller page range.")
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: pcm)
        pcmByteCount += UInt32(pcm.count)
    }

    func finish() throws {
        guard !finished else { return }
        try writeUInt32(36 + pcmByteCount, at: 4)
        try writeUInt32(pcmByteCount, at: 40)
        try handle.close()
        finished = true
    }

    func cancel() {
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
        finished = true
    }

    private func writeUInt32(_ value: UInt32, at offset: UInt64) throws {
        var littleEndian = value.littleEndian
        let data = withUnsafeBytes(of: &littleEndian) { Data($0) }
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: data)
    }

    deinit {
        if !finished { cancel() }
    }
}
