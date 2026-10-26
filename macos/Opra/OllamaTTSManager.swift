import Foundation
import Combine

@MainActor
final class OllamaTTSManager: ObservableObject, TTSEngine {
    let provider: TTSProvider = .ollama
    @Published private(set) var availableVoices = ["default"]
    @Published private(set) var isChecking = false
    @Published private(set) var connectionMessage: String?

    static var isSupported: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    private let controller = AudioPlaybackController()
    private let client = OllamaSpeechClient()
    private weak var settings: SettingsManager?
    private var cancellable: AnyCancellable?
    private var runVoice = "default"

    init() {
        controller.split = { text in
            SpeechTextChunker.split(text).map {
                .init(text: $0.text, startWordIndex: $0.startWordIndex, wordCount: $0.wordCount)
            }
        }
        controller.produceAudio = { [weak self] chunk in
            guard let self else { throw CancellationError() }
            return try await self.client.speech(text: chunk.text, voice: self.runVoice)
        }
        cancellable = controller.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isSpeaking: Bool { controller.isSpeaking }
    var isPaused: Bool { controller.isPaused }
    var isProcessing: Bool { controller.isProcessing }
    var errorMessage: String? { controller.errorMessage }
    var readingProgress: Double { controller.readingProgress }
    var currentWordIndex: Int { controller.currentWordIndex }
    var totalWords: Int { controller.totalWords }
    var elapsedTime: TimeInterval { controller.elapsedTime }
    var speechRate: Float { controller.speechRate }
    var currentChunkIndex: Int { controller.currentDocumentChunkIndex }

    func setSettingsManager(_ settings: SettingsManager) {
        self.settings = settings
        controller.settingsManager = settings
        controller.setRate(settings.speechRate)
    }
    func setPDFExtractor(_ extractor: PDFTextExtractor) { controller.pdfExtractor = extractor }

    func refreshVoices() async {
        guard !isChecking else { return }
        guard Self.isSupported else {
            connectionMessage = "Ollama speech currently requires an Apple Silicon Mac."
            return
        }
        isChecking = true
        connectionMessage = nil
        defer { isChecking = false }
        do {
            availableVoices = try await client.voices()
            connectionMessage = "Phonon is ready — \(availableVoices.count) voices available."
        } catch is CancellationError {
            return
        } catch {
            connectionMessage = error.localizedDescription
        }
    }

    private func prepare() -> Bool {
        controller.stop()
        guard Self.isSupported else {
            controller.fail("Ollama speech currently requires an Apple Silicon Mac. Choose System or OpenAI on this Mac.")
            return false
        }
        // Keep a consistent voice throughout the current document run.
        runVoice = settings?.ollamaTTSVoice ?? "default"
        return true
    }
    func speak(_ text: String) {
        guard prepare() else { return }
        controller.speak(text)
    }
    func speakChunkedText(_ texts: [String], startChunk: Int = 0) {
        guard prepare() else { return }
        controller.speakChunked(texts, startChunk: startChunk)
    }
    func pauseSpeaking() { controller.pause() }
    func resumeSpeaking() { controller.resume() }
    func stopSpeaking() { controller.stop() }
    func setSpeechRate(_ rate: Float) { controller.setRate(rate) }
    func previewSpeed(_ rate: Float) {
        controller.setRate(rate)
        speak("Hello from Opra. This is a preview of your Phonon reading voice.")
    }
}
