//
//  TTSEngine.swift
//  Opra
//
//  Common interface for every text-to-speech provider. The core protocol covers
//  only the transport-agnostic surface that TTSProviderManager forwards to the
//  active engine; provider-specific features live in capability sub-protocols that
//  callers query with `as?`, so the core never bloats as providers are added.
//

import Foundation
import AVFoundation

/// The text-to-speech backends the user can choose between.
enum TTSProvider: String, CaseIterable, Identifiable {
    case system = "System TTS"
    case openAI = "OpenAI TTS"
    case kokoro = "Kokoro (On-Device)"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .system:
            return "Uses macOS built-in text-to-speech voices"
        case .openAI:
            return "Uses OpenAI's latest speech model for higher-quality generated voices"
        case .kokoro:
            return "Runs the open-source Kokoro neural voice fully on your Mac — no internet required"
        }
    }

    /// Where the synthesis runs — drives the badge shown in Settings.
    enum Kind { case builtIn, cloud, onDevice }

    var kind: Kind {
        switch self {
        case .system: return .builtIn
        case .openAI: return .cloud
        case .kokoro: return .onDevice
        }
    }
}

/// The surface every engine implements. `TTSProviderManager` forwards to the active
/// engine through this protocol, so none of these members may involve provider-specific
/// concepts.
@MainActor
protocol TTSEngine: AnyObject, ObservableObject {
    var provider: TTSProvider { get }

    // Transport-agnostic playback state.
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    var isProcessing: Bool { get }
    var errorMessage: String? { get }
    var readingProgress: Double { get }
    var currentWordIndex: Int { get }
    var totalWords: Int { get }
    var elapsedTime: TimeInterval { get }
    var speechRate: Float { get }
    /// Index of the chunk (= passage, in the reading-script model) currently being read.
    var currentChunkIndex: Int { get }

    // Lifecycle wiring.
    func setSettingsManager(_ settings: SettingsManager)
    func setPDFExtractor(_ extractor: PDFTextExtractor)

    // Commands.
    func speak(_ text: String)
    func speakChunkedText(_ texts: [String], startChunk: Int)
    func pauseSpeaking()
    func resumeSpeaking()
    func stopSpeaking()
    func setSpeechRate(_ rate: Float)
    func previewSpeed(_ rate: Float)
}

/// Engines that expose a selectable list of `AVSpeechSynthesisVoice`s (System TTS).
@MainActor
protocol VoiceSelectingEngine: TTSEngine {
    var currentVoice: AVSpeechSynthesisVoice? { get }
    var availableVoices: [AVSpeechSynthesisVoice] { get }
    func setVoice(_ voice: AVSpeechSynthesisVoice)
    func previewVoice(_ voice: AVSpeechSynthesisVoice)
}

/// Engines that support Apple Personal Voice (System TTS).
@MainActor
protocol PersonalVoiceEngine: TTSEngine {
    var isPersonalVoiceAuthorized: Bool { get }
    var personalVoiceStatus: String { get }
    func requestPersonalVoiceAuthorization()
    func checkPersonalVoiceAuthorization()
}

/// Engines that accept SSML markup (System TTS).
@MainActor
protocol SSMLCapableEngine: TTSEngine {
    var enableSSML: Bool { get }
    func setSSMLEnabled(_ enabled: Bool)
}

/// Lifecycle of an on-device model that has to be downloaded before first use.
enum ModelInstallState: Equatable {
    case notInstalled
    case downloading(Double)   // 0...1 progress
    case installed
    case failed(String)
}

/// Engines that download and manage an on-device model (Kokoro).
@MainActor
protocol InstallableEngine: TTSEngine {
    var installState: ModelInstallState { get }
    var isReady: Bool { get }
    func ensureModelInstalled()
    func cancelInstall()
}
