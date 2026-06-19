//
//  OpenAITTSManager.swift
//  Opra
//
//  OpenAI cloud TTS provider. A thin TTSEngine that owns a shared
//  AudioPlaybackController and supplies it with two things: how to split text into
//  request-sized speech chunks, and how to produce audio Data for a chunk (a call to
//  the OpenAI /v1/audio/speech endpoint). All playback/progress/elapsed bookkeeping
//  lives in the controller.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class OpenAITTSManager: ObservableObject, TTSEngine {
    let provider: TTSProvider = .openAI

    @Published var isConfigured: Bool = false

    private let controller = AudioPlaybackController()
    private let apiURL = URL(string: "https://api.openai.com/v1/audio/speech")!
    private let maxRequestCharacters = 3_600
    private weak var settingsManager: SettingsManager?
    private var cancellable: AnyCancellable?

    init() {
        controller.split = { [weak self] text in
            guard let self else { return [] }
            return self.splitTextForSpeech(self.preprocessTextForTTS(text))
        }
        controller.produceAudio = { [weak self] chunk in
            guard let self else { throw TTSProduceError(message: "OpenAI manager unavailable.") }
            return try await self.requestSpeech(for: chunk.text)
        }
        // Re-emit the controller's state changes so SwiftUI views observing this
        // manager (and TTSProviderManager) refresh — same fan-in pattern as before.
        cancellable = controller.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - TTSEngine forwarded state
    var isSpeaking: Bool { controller.isSpeaking }
    var isPaused: Bool { controller.isPaused }
    var isProcessing: Bool { controller.isProcessing }
    var errorMessage: String? { controller.errorMessage }
    var readingProgress: Double { controller.readingProgress }
    var currentWordIndex: Int { controller.currentWordIndex }
    var totalWords: Int { controller.totalWords }
    var elapsedTime: TimeInterval { controller.elapsedTime }
    var speechRate: Float { controller.speechRate }

    /// Active passage index, used by the reading-script UI for passage highlighting.
    var currentChunkIndex: Int { controller.currentDocumentChunkIndex }

    func setSettingsManager(_ settings: SettingsManager) {
        settingsManager = settings
        controller.settingsManager = settings
        controller.setRate(settings.speechRate)
        refreshConfiguration()
    }

    func setPDFExtractor(_ extractor: PDFTextExtractor) {
        controller.pdfExtractor = extractor
    }

    func refreshConfiguration() {
        isConfigured = !(settingsManager?.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    // MARK: - Commands
    func speak(_ text: String) {
        guard ensureConfigured() else { return }
        applyDefaultInstructionsIfNeeded()
        controller.speak(text)
    }

    func speakChunkedText(_ texts: [String], startChunk: Int = 0) {
        guard ensureConfigured() else { return }
        applyDefaultInstructionsIfNeeded()
        controller.speakChunked(texts, startChunk: startChunk)
    }

    func pauseSpeaking() { controller.pause() }
    func resumeSpeaking() { controller.resume() }
    func stopSpeaking() { controller.stop() }
    func setSpeechRate(_ rate: Float) { controller.setRate(rate) }

    func previewSpeed(_ rate: Float) {
        controller.setRate(rate)
        speak("This is a preview of the selected OpenAI voice and reading speed.")
    }

    // MARK: - Configuration helpers
    private func ensureConfigured() -> Bool {
        refreshConfiguration()
        guard isConfigured else {
            controller.fail("Add an OpenAI API key in Settings to use OpenAI voices.")
            return false
        }
        return true
    }

    private func applyDefaultInstructionsIfNeeded() {
        guard let settingsManager else { return }
        if settingsManager.openAITTSInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settingsManager.setOpenAITTSInstructions("Read clearly with a natural, warm audiobook tone.")
        }
    }

    // MARK: - Audio production
    private func requestSpeech(for text: String) async throws -> Data {
        guard let settingsManager else { throw TTSProduceError(message: "OpenAI settings are unavailable.") }
        let apiKey = settingsManager.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw TTSProduceError(message: "Add an OpenAI API key in Settings to use OpenAI voices.")
        }

        let instructions = settingsManager.openAITTSInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = [
            "model": settingsManager.openAITTSModel,
            "voice": settingsManager.openAITTSVoice,
            "input": text,
            "instructions": instructions,
            "response_format": "mp3"
        ]

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TTSProduceError(message: "OpenAI speech request returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode), !data.isEmpty else {
            let details = String(data: data, encoding: .utf8) ?? "No response body."
            throw TTSProduceError(message: "OpenAI speech request failed with status \(http.statusCode): \(details)")
        }
        return data
    }

    // MARK: - Text processing (OpenAI request char limit)
    private func splitTextForSpeech(_ text: String) -> [AudioPlaybackController.SpeechChunk] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }

        var chunks: [AudioPlaybackController.SpeechChunk] = []
        var currentText = ""
        var currentWordCount = 0
        var currentStartWordIndex = 0

        for word in words {
            let candidate = currentText.isEmpty ? word : "\(currentText) \(word)"
            if candidate.count > maxRequestCharacters, !currentText.isEmpty {
                chunks.append(.init(text: currentText, startWordIndex: currentStartWordIndex, wordCount: currentWordCount))
                currentStartWordIndex += currentWordCount
                currentText = word
                currentWordCount = 1
            } else {
                currentText = candidate
                currentWordCount += 1
            }
        }

        if !currentText.isEmpty {
            chunks.append(.init(text: currentText, startWordIndex: currentStartWordIndex, wordCount: currentWordCount))
        }
        return chunks
    }

    private func preprocessTextForTTS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[\u{00}-\u{08}\u{0B}\u{0C}\u{0E}-\u{1F}\u{7F}]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[\u{00A0}\u{2000}-\u{200F}\u{2028}-\u{202F}\u{205F}-\u{206F}\u{3000}]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
