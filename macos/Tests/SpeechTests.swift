import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct TestFailure: Error { let message: String }
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(message: message) }
}

/// URLProtocol keeps tests offline: no installed models, API keys or audio device.
private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@main
struct SpeechTests {
    static func main() async throws {
        try testChunks()
        try testWAV()
        try testModelOptions()
        try await testOllama()
        print("PASS: speech chunking, WAV, model compatibility and Ollama HTTP regression tests")
    }

    static func testChunks() throws {
        try expect(SpeechTextChunker.split(" \n\t").isEmpty, "Whitespace produces no requests")
        for limit in [400, 1_200, 3_600] {
            let text = Array(repeating: "A PDF sentence with accents: café. Another sentence!", count: 400).joined(separator: "\n")
            let chunks = SpeechTextChunker.split(text, limit: limit)
            try expect(chunks.count > 1, "Long pages are split")
            try expect(chunks.allSatisfy { !$0.text.isEmpty && $0.text.unicodeScalars.count <= limit }, "Every request fits")
            let originalWords = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let spokenWords = chunks.flatMap { $0.text.split(separator: " ").map(String.init) }
            try expect(originalWords == spokenWords, "No skipped, duplicated or reordered words")
            var nextWord = 0
            for chunk in chunks {
                try expect(chunk.startWordIndex == nextWord, "Highlight offsets remain contiguous")
                nextWord += chunk.wordCount
            }
            try expect(nextWord == originalWords.count, "Word totals remain exact")

            let token = String(repeating: "a\u{0301}", count: 5_000)
            let pieces = SpeechTextChunker.split(token, limit: limit)
            try expect(pieces.map(\.text).joined() == token, "Oversized Unicode token is preserved")
            try expect(pieces.allSatisfy { $0.text.unicodeScalars.count <= limit }, "Unicode uses server character accounting")
            try expect(pieces.reduce(0) { $0 + $1.wordCount } == 1, "A split token is still one PDF word")
        }
    }

    static func testWAV() throws {
        let pcm = Data([0, 0, 255, 127, 0, 128])
        let wav = AudioWAV.data(fromMonoInt16PCM: pcm, sampleRate: 24_000)
        func u32(_ offset: Int) -> UInt32 {
            (0..<4).reduce(0) { $0 | UInt32(wav[offset + $1]) << ($1 * 8) }
        }
        try expect(wav.count == 50, "44-byte WAV header plus unchanged PCM")
        try expect(String(data: wav.prefix(4), encoding: .utf8) == "RIFF", "RIFF signature")
        try expect(u32(4) == 42 && u32(40) == 6, "Finite WAV lengths for AVAudioPlayer")
        try expect(u32(24) == 24_000 && u32(28) == 48_000, "24kHz mono 16-bit format")
        try expect(wav.suffix(6) == pcm, "PCM bytes preserved exactly")
        let kokoro = AudioWAV.data(fromMonoFloat: [0, 1, -1], sampleRate: 24_000)
        try expect(kokoro.count == 50, "Existing Kokoro WAV conversion preserved")
    }

    static func testModelOptions() throws {
        try expect(OpenAISpeechOptions.validVoice("marin", model: "tts-1") == "alloy", "Legacy voice normalized")
        try expect(OpenAISpeechOptions.validVoice("cedar", model: "gpt-4o-mini-tts") == "cedar", "Modern voice retained")
        try expect(!OpenAISpeechOptions.supportsInstructions("tts-1-hd"), "Legacy models omit instructions")
        try expect(!OpenAISpeechOptions.voices(for: "tts-1").contains("marin"), "Picker excludes unsupported voices")
        for version in ["0.40.11", "0.40.12", "0.41.0", "1.0.0"] {
            try expect(OllamaSpeechClient.supportsSpeech(version), "Supported version \(version)")
        }
        for version in ["0.40.10", "0.9.99", "garbage", "0.40.11-rc0", "0.x.40.11"] {
            try expect(!OllamaSpeechClient.supportsSpeech(version), "Rejected version \(version)")
        }
    }

    static func testOllama() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = OllamaSpeechClient(session: session)
        StubProtocol.handler = { request in
            try expect(request.url?.host == "localhost" && request.url?.port == 11434, "Local endpoint only")
            try expect(request.value(forHTTPHeaderField: "Authorization") == nil, "No OpenAI key sent to Ollama")
            if request.url?.path == "/api/version" {
                return (200, Data(#"{"version":"0.40.11"}"#.utf8))
            }
            return (200, Data(#"{"capabilities":["speech"],"voices":["Hugh","Zoey","default","Hugh"]}"#.utf8))
        }
        let voices = try await client.voices()
        try expect(voices == ["default", "Hugh", "Zoey"], "Voice discovery and deduplication")
        StubProtocol.handler = { request in
            try expect(request.url?.path == "/v1/audio/speech" && request.httpMethod == "POST", "Speech route")
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let json = try JSONSerialization.jsonObject(with: body) as! [String: String]
            try expect(json == ["model": "phonon", "input": "Hello", "voice": "Hugh", "response_format": "pcm"], "Exact supported payload")
            return (200, Data([0, 0, 1, 0]))
        }
        let wav = try await client.speech(text: "Hello", voice: "Hugh")
        try expect(wav.count == 48, "PCM response wrapped for playback")

        for (status, data, message) in [
            (404, Data(), "ollama pull phonon"),
            (400, Data(#"{"error":{"message":"unknown voice"}}"#.utf8), "unknown voice"),
            (500, Data(#"{"error":"model failed"}"#.utf8), "model failed"),
            (200, Data(), "empty or incomplete"),
            (200, Data([1]), "empty or incomplete")
        ] {
            StubProtocol.handler = { _ in (status, data) }
            do {
                _ = try await client.speech(text: "Hello", voice: "default")
                throw TestFailure(message: "Expected HTTP/audio failure")
            } catch let error as OllamaSpeechError {
                try expect(error.message.contains(message), "Actionable error: \(message)")
            }
        }
        StubProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await client.voices()
            throw TestFailure(message: "Expected connection failure")
        } catch let error as OllamaSpeechError {
            try expect(error.message.contains("Open Ollama"), "Offline setup guidance")
        }
        StubProtocol.handler = { _ in throw URLError(.cancelled) }
        do {
            _ = try await client.speech(text: "Hello", voice: "default")
            throw TestFailure(message: "Expected cancellation")
        } catch is CancellationError {}
    }
}
