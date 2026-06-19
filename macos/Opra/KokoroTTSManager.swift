//
//  KokoroTTSManager.swift
//  Opra
//
//  On-device TTS provider backed by KokoroSwift (MLX). A thin TTSEngine that drives a
//  shared AudioPlaybackController: each passage is synthesized in-process (off the main
//  thread) to 24 kHz Float PCM, wrapped as WAV, and played like the OpenAI provider.
//  Requires Apple Silicon and a downloaded model (managed by KokoroModelInstaller).
//

import Foundation
import AVFoundation
import Combine
import KokoroSwift
import MLX

@MainActor
final class KokoroTTSManager: ObservableObject, TTSEngine, InstallableEngine {
    let provider: TTSProvider = .kokoro

    let installer = KokoroModelInstaller()
    @Published var selectedVoice: String = KokoroModelInstaller.voiceNames.first ?? "af_heart"

    private let controller = AudioPlaybackController()
    private let box = KokoroEngineBox()
    private let inferenceQueue = DispatchQueue(label: "opra.kokoro.inference", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()

    static var isSupported: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    init() {
        controller.split = { [weak self] text in self?.split(text) ?? [] }
        controller.produceAudio = { [weak self] chunk in
            guard let self else { throw TTSProduceError(message: "Kokoro engine unavailable.") }
            return try await self.synthesize(chunk.text)
        }
        controller.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        installer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
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
    var currentChunkIndex: Int { controller.currentDocumentChunkIndex }

    // MARK: - InstallableEngine
    var installState: ModelInstallState { installer.state }
    var isReady: Bool { Self.isSupported && installer.state == .installed }
    func ensureModelInstalled() { installer.install() }
    func cancelInstall() { installer.cancel() }

    // MARK: - Lifecycle
    func setSettingsManager(_ settings: SettingsManager) {
        controller.settingsManager = settings
        controller.setRate(settings.speechRate)
    }
    func setPDFExtractor(_ extractor: PDFTextExtractor) { controller.pdfExtractor = extractor }

    // MARK: - Commands
    func speak(_ text: String) {
        guard ensureReady() else { return }
        controller.speak(text)
    }
    func speakChunkedText(_ texts: [String], startChunk: Int = 0) {
        guard ensureReady() else { return }
        controller.speakChunked(texts, startChunk: startChunk)
    }
    func pauseSpeaking() { controller.pause() }
    func resumeSpeaking() { controller.resume() }
    func stopSpeaking() { controller.stop() }
    func setSpeechRate(_ rate: Float) { controller.setRate(rate) }
    func previewSpeed(_ rate: Float) {
        controller.setRate(rate)
        speak("This is a preview of the on-device Kokoro voice and reading speed.")
    }

    func setVoice(_ name: String) {
        selectedVoice = name
        box.invalidateVoice()
    }

    // MARK: - Helpers
    private func ensureReady() -> Bool {
        guard Self.isSupported else {
            controller.fail("On-device Kokoro requires an Apple Silicon Mac.")
            return false
        }
        switch installer.state {
        case .installed:
            return true
        case .notInstalled:
            installer.install()   // start the one-time download so the user sees progress
            controller.fail("Downloading the on-device voice (~330 MB). Playback will be ready when it finishes.")
            return false
        case .downloading(let p):
            controller.fail("The on-device voice is still downloading… \(Int(p * 100))%. Please wait.")
            return false
        case .failed(let message):
            controller.fail("On-device voice download failed: \(message)")
            return false
        }
    }

    /// One speech chunk per passage; word counts feed progress tracking.
    private func split(_ text: String) -> [AudioPlaybackController.SpeechChunk] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        guard words > 0 else { return [] }
        return [.init(text: text, startWordIndex: 0, wordCount: words)]
    }

    private func synthesize(_ text: String) async throws -> Data {
        let modelURL = installer.modelURL
        let voiceURL = installer.voiceURL(selectedVoice)
        let voiceName = selectedVoice
        let box = self.box
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            inferenceQueue.async {
                do {
                    let samples = try box.synthesize(text: text, modelURL: modelURL,
                                                     voiceURL: voiceURL, voiceName: voiceName)
                    cont.resume(returning: AudioWAV.data(fromMonoFloat: samples, sampleRate: 24_000))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

/// Holds the loaded KokoroTTS engine + voice. Accessed only on the serial inference
/// queue, so it is safe to treat as Sendable despite KokoroTTS/MLXArray not being so.
private final class KokoroEngineBox: @unchecked Sendable {
    private var engine: KokoroTTS?
    private var voice: MLXArray?
    private var loadedVoiceName: String?
    private let lock = NSLock()

    func invalidateVoice() {
        lock.lock(); voice = nil; loadedVoiceName = nil; lock.unlock()
    }

    func synthesize(text: String, modelURL: URL, voiceURL: URL, voiceName: String) throws -> [Float] {
        if engine == nil {
            engine = KokoroTTS(modelPath: modelURL)
        }
        if voice == nil || loadedVoiceName != voiceName {
            let arrays = try MLX.loadArrays(url: voiceURL)
            guard let array = arrays.values.first else {
                throw TTSProduceError(message: "Could not load the Kokoro voice file.")
            }
            voice = array
            loadedVoiceName = voiceName
        }
        let (samples, _) = try engine!.generateAudio(voice: voice!, language: .enUS, text: text, speed: 1.0)
        return samples
    }
}
