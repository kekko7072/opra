//
//  TTSProviderManager.swift
//  Opra
//
//  Facade over the available TTS engines. Holds the concrete managers (some views
//  need provider-specific UI) plus a protocol-typed engine map, and forwards the
//  common surface to the active engine. Provider-specific features are forwarded
//  only when the active engine advertises the matching capability.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class TTSProviderManager: ObservableObject {
    /// Stays a settable @Published so SwiftUI `Picker(selection:)` can bind to it.
    /// The choice is persisted so the app reopens with the same voice provider.
    @Published var currentProvider: TTSProvider = .system {
        didSet {
            guard currentProvider != oldValue else { return }
            UserDefaults.standard.set(currentProvider.rawValue, forKey: Self.providerDefaultsKey)
        }
    }

    private static let providerDefaultsKey = "selectedTTSProvider"

    // Concrete references for views that drive provider-specific UI
    // (VoicePickerView needs the system manager; SettingsView calls OpenAI.refreshConfiguration()).
    let systemTTSManager: TextToSpeechManager
    let openAITTSManager: OpenAITTSManager
    let kokoroTTSManager: KokoroTTSManager

    private var engines: [TTSProvider: any TTSEngine]
    private var current: any TTSEngine { engines[currentProvider] ?? systemTTSManager }
    private var cancellables = Set<AnyCancellable>()

    init() {
        let system = TextToSpeechManager()
        let openAI = OpenAITTSManager()
        let kokoro = KokoroTTSManager()
        systemTTSManager = system
        openAITTSManager = openAI
        kokoroTTSManager = kokoro
        engines = [.system: system, .openAI: openAI, .kokoro: kokoro]

        // Restore the saved provider; default to on-device Kokoro where it's supported.
        // (Assigning in init doesn't fire `didSet`, so the default isn't persisted until
        // the user actually picks a provider.)
        if let raw = UserDefaults.standard.string(forKey: Self.providerDefaultsKey),
           let saved = TTSProvider(rawValue: raw) {
            currentProvider = saved
        } else if KokoroTTSManager.isSupported {
            currentProvider = .kokoro
        }

        // Re-emit each engine's changes as our own so SwiftUI refreshes on provider state.
        system.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        openAI.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        kokoro.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    // MARK: - Forwarded playback state
    var isSpeaking: Bool { current.isSpeaking }
    var isPaused: Bool { current.isPaused }
    var isProcessing: Bool { current.isProcessing }
    var errorMessage: String? { current.errorMessage }
    var readingProgress: Double { current.readingProgress }
    var currentWordIndex: Int { current.currentWordIndex }
    var totalWords: Int { current.totalWords }
    var elapsedTime: TimeInterval { current.elapsedTime }
    var speechRate: Float { current.speechRate }
    var currentChunkIndex: Int { current.currentChunkIndex }

    // MARK: - Commands
    func speak(_ text: String) { current.speak(text) }
    func speakChunkedText(_ texts: [String], startChunk: Int = 0) {
        current.speakChunkedText(texts, startChunk: startChunk)
    }
    func pauseSpeaking() { current.pauseSpeaking() }
    func resumeSpeaking() { current.resumeSpeaking() }
    func stopSpeaking() { current.stopSpeaking() }
    func setSpeechRate(_ rate: Float) { current.setSpeechRate(rate) }
    func previewSpeed(_ rate: Float) { current.previewSpeed(rate) }

    func setSettingsManager(_ settings: SettingsManager) {
        engines.values.forEach { $0.setSettingsManager(settings) }
    }
    func setPDFExtractor(_ extractor: PDFTextExtractor) {
        engines.values.forEach { $0.setPDFExtractor(extractor) }
    }

    func setProvider(_ provider: TTSProvider) {
        guard provider != currentProvider else { return }
        // Reflect the choice immediately so the picker updates without flicker (and it
        // persists via `currentProvider`'s observer).
        currentProvider = provider
        // Stop whichever engine was mid-utterance on the next main-actor turn. Doing it
        // synchronously here cascades published resets out of AudioPlaybackController
        // while SwiftUI is still processing the picker's update, which it warns about
        // ("Publishing changes from within view updates is not allowed").
        Task { @MainActor [weak self] in
            self?.engines.values.forEach { engine in
                if engine.isSpeaking || engine.isProcessing { engine.stopSpeaking() }
            }
        }
    }

    // MARK: - Capability-gated forwards (safe defaults when the active engine lacks it)
    var currentVoice: AVSpeechSynthesisVoice? { (current as? any VoiceSelectingEngine)?.currentVoice }
    var availableVoices: [AVSpeechSynthesisVoice] { (current as? any VoiceSelectingEngine)?.availableVoices ?? [] }
    func setVoice(_ voice: AVSpeechSynthesisVoice) { (current as? any VoiceSelectingEngine)?.setVoice(voice) }
    func previewVoice(_ voice: AVSpeechSynthesisVoice) { (current as? any VoiceSelectingEngine)?.previewVoice(voice) }

    var isPersonalVoiceAuthorized: Bool { (current as? any PersonalVoiceEngine)?.isPersonalVoiceAuthorized ?? false }
    var personalVoiceStatus: String { (current as? any PersonalVoiceEngine)?.personalVoiceStatus ?? "Not supported" }
    func requestPersonalVoiceAuthorization() { (current as? any PersonalVoiceEngine)?.requestPersonalVoiceAuthorization() }
    func checkPersonalVoiceAuthorization() { (current as? any PersonalVoiceEngine)?.checkPersonalVoiceAuthorization() }

    var enableSSML: Bool { (current as? any SSMLCapableEngine)?.enableSSML ?? false }
    func setSSMLEnabled(_ enabled: Bool) { (current as? any SSMLCapableEngine)?.setSSMLEnabled(enabled) }
}
