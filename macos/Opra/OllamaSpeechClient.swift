import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct OllamaSpeechError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Local-only Phonon integration. No API key, cloud fallback, or model download.
struct OllamaSpeechClient {
    static let model = "phonon"
    static let minimumVersion = "0.40.11"
    private let session: URLSession
    private let baseURL = URL(string: "http://localhost:11434")!

    init(session: URLSession = .shared) { self.session = session }

    func voices() async throws -> [String] {
        struct Version: Decodable { let version: String }
        let versionData = try await send(path: "api/version")
        let version = try JSONDecoder().decode(Version.self, from: versionData).version
        guard Self.supportsSpeech(version) else {
            throw OllamaSpeechError(message: "Update Ollama to \(Self.minimumVersion) or later to use Phonon voices.")
        }
        struct Model: Decodable {
            let capabilities: [String]?
            let voices: [String]?
        }
        let data = try await send(path: "api/show", body: ["model": Self.model])
        let model = try JSONDecoder().decode(Model.self, from: data)
        guard model.capabilities?.contains("speech") == true else {
            throw OllamaSpeechError(message: "Phonon does not report speech support. Update Ollama and run ollama pull phonon.")
        }
        return ["default"] + Set(model.voices ?? [])
            .filter { !$0.isEmpty && $0 != "default" }.sorted()
    }

    func speech(text: String, voice: String) async throws -> Data {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.unicodeScalars.count <= 4_096 else {
            throw OllamaSpeechError(message: "Speech requests must contain between 1 and 4,096 characters.")
        }
        // Ollama's streamed WAV has unknown-length headers. Request PCM and build
        // a finite WAV after each chunk, so AVAudioPlayer reports a correct duration.
        let pcm = try await send(path: "v1/audio/speech", body: [
            "model": Self.model, "input": text, "voice": voice,
            "response_format": "pcm"
        ])
        guard !pcm.isEmpty, pcm.count.isMultiple(of: 2) else {
            throw OllamaSpeechError(message: "Ollama returned empty or incomplete speech audio. Try again.")
        }
        return AudioWAV.data(fromMonoInt16PCM: pcm, sampleRate: 24_000)
    }

    static func supportsSpeech(_ version: String) -> Bool {
        // Prereleases of the minimum version may not contain the full voice catalog.
        let parts = version.split(separator: "-", maxSplits: 1)
        let components = (parts.first ?? "").split(separator: ".")
        let numbers = components.compactMap { Int($0) }
        guard components.count == 3, numbers.count == 3 else { return false }
        let minimum = [0, 40, 11]
        for (actual, required) in zip(numbers, minimum) {
            if actual != required { return actual > required }
        }
        return parts.count == 1
    }

    private func send(path: String, body: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = body?["input"] == nil ? 10 : 180
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw OllamaSpeechError(message: "Ollama returned an invalid response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 404 {
                    throw OllamaSpeechError(message: "Phonon or the speech endpoint was not found. Update Ollama to \(Self.minimumVersion) or later, then run ollama pull phonon.")
                }
                let details = Self.errorDetails(data)
                throw OllamaSpeechError(message: "Ollama request failed (\(http.statusCode)): \(details)")
            }
            return data
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut {
                throw OllamaSpeechError(message: "Ollama took too long to respond. Check that Phonon is installed and try again.")
            }
            throw OllamaSpeechError(message: "Cannot connect to Ollama at localhost:11434. Open Ollama on this Mac and try again.")
        }
    }

    private static func errorDetails(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? String { return String(error.prefix(500)) }
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return String(message.prefix(500))
            }
        }
        return "Check Ollama and the selected voice in Settings."
    }
}
