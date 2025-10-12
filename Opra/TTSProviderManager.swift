//
//  TTSProviderManager.swift
//  Opra
//
//  Created by Francesco Vezzani on 12/10/25.
//

import Foundation
import AVFoundation
import Combine

enum TTSProvider: String, CaseIterable {
    case system = "System TTS"
    case ollama = "Ollama TTS"
    
    var description: String {
        switch self {
        case .system:
            return "Uses macOS built-in text-to-speech voices"
        case .ollama:
            return "Uses Ollama AI models for high-quality speech synthesis"
        }
    }
}

@MainActor
class TTSProviderManager: ObservableObject {
    @Published var currentProvider: TTSProvider = .system
    @Published var systemTTSManager: TextToSpeechManager
    @Published var ollamaTTSManager: OllamaTTSManager
    
    init() {
        self.systemTTSManager = TextToSpeechManager()
        self.ollamaTTSManager = OllamaTTSManager()
        
        // Forward state changes from underlying managers
        systemTTSManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        ollamaTTSManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // Computed properties to expose current provider's state
    var isSpeaking: Bool {
        switch currentProvider {
        case .system:
            return systemTTSManager.isSpeaking
        case .ollama:
            return ollamaTTSManager.isSpeaking
        }
    }
    
    var isPaused: Bool {
        switch currentProvider {
        case .system:
            return systemTTSManager.isPaused
        case .ollama:
            return ollamaTTSManager.isPaused
        }
    }
    
    var readingProgress: Double {
        switch currentProvider {
        case .system:
            return systemTTSManager.readingProgress
        case .ollama:
            return ollamaTTSManager.readingProgress
        }
    }
    
    var currentWordIndex: Int {
        switch currentProvider {
        case .system:
            return systemTTSManager.currentWordIndex
        case .ollama:
            return ollamaTTSManager.currentWordIndex
        }
    }
    
    var totalWords: Int {
        switch currentProvider {
        case .system:
            return systemTTSManager.totalWords
        case .ollama:
            return ollamaTTSManager.totalWords
        }
    }
    
    var elapsedTime: TimeInterval {
        switch currentProvider {
        case .system:
            return systemTTSManager.elapsedTime
        case .ollama:
            return ollamaTTSManager.elapsedTime
        }
    }
    
    var speechRate: Float {
        switch currentProvider {
        case .system:
            return systemTTSManager.speechRate
        case .ollama:
            return ollamaTTSManager.speechRate
        }
    }
    
    var currentVoice: AVSpeechSynthesisVoice? {
        return systemTTSManager.currentVoice
    }
    
    func setProvider(_ provider: TTSProvider) {
        currentProvider = provider
        
        // Stop current speech when switching providers
        if systemTTSManager.isSpeaking {
            systemTTSManager.stopSpeaking()
        }
        if ollamaTTSManager.isSpeaking {
            ollamaTTSManager.stopSpeaking()
        }
    }
    
    func speak(_ text: String) {
        switch currentProvider {
        case .system:
            systemTTSManager.speak(text)
        case .ollama:
            // Check if Ollama is available and has a valid model
            if ollamaTTSManager.isAvailable && !ollamaTTSManager.selectedModel.isEmpty {
                ollamaTTSManager.speak(text)
            } else {
                // Fall back to system TTS if Ollama is not available
                print("Ollama TTS not available, falling back to System TTS")
                systemTTSManager.speak(text)
            }
        }
    }
    
    func speakChunkedText(_ texts: [String], startChunk: Int = 0) {
        switch currentProvider {
        case .system:
            systemTTSManager.speakChunkedText(texts, startChunk: startChunk)
        case .ollama:
            // For Ollama, we'll fall back to system TTS for chunked text
            // since Ollama TTS is not fully implemented
            print("Using System TTS for chunked text (Ollama not fully implemented)")
            systemTTSManager.speakChunkedText(texts, startChunk: startChunk)
        }
    }
    
    func pauseSpeaking() {
        switch currentProvider {
        case .system:
            systemTTSManager.pauseSpeaking()
        case .ollama:
            ollamaTTSManager.pauseSpeaking()
        }
    }
    
    func resumeSpeaking() {
        switch currentProvider {
        case .system:
            systemTTSManager.resumeSpeaking()
        case .ollama:
            ollamaTTSManager.resumeSpeaking()
        }
    }
    
    func stopSpeaking() {
        switch currentProvider {
        case .system:
            systemTTSManager.stopSpeaking()
        case .ollama:
            ollamaTTSManager.stopSpeaking()
        }
    }
    
    func setSpeechRate(_ rate: Float) {
        switch currentProvider {
        case .system:
            systemTTSManager.setSpeechRate(rate)
        case .ollama:
            ollamaTTSManager.setSpeechRate(rate)
        }
    }
    
    var availableVoices: [AVSpeechSynthesisVoice] {
        switch currentProvider {
        case .system:
            return systemTTSManager.availableVoices
        case .ollama:
            return []
        }
    }
    
    var isPersonalVoiceAuthorized: Bool {
        switch currentProvider {
        case .system:
            return systemTTSManager.isPersonalVoiceAuthorized
        case .ollama:
            return false // Ollama doesn't support personal voice
        }
    }
    
    var personalVoiceStatus: String {
        switch currentProvider {
        case .system:
            return systemTTSManager.personalVoiceStatus
        case .ollama:
            return "Not supported"
        }
    }
    
    var enableSSML: Bool {
        switch currentProvider {
        case .system:
            return systemTTSManager.enableSSML
        case .ollama:
            return false // Ollama doesn't support SSML
        }
    }
    
    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        switch currentProvider {
        case .system:
            systemTTSManager.setVoice(voice)
        case .ollama:
            // Ollama doesn't use system voices
            break
        }
    }
    
    func previewVoice(_ voice: AVSpeechSynthesisVoice) {
        switch currentProvider {
        case .system:
            systemTTSManager.previewVoice(voice)
        case .ollama:
            // Ollama doesn't use system voices
            break
        }
    }
    
    func previewSpeed(_ rate: Float) {
        switch currentProvider {
        case .system:
            systemTTSManager.previewSpeed(rate)
        case .ollama:
            ollamaTTSManager.setSpeechRate(rate)
            // For Ollama, we could generate a short preview
            let previewText = "This is a preview of the reading speed. How does this pace sound to you?"
            ollamaTTSManager.speak(previewText)
        }
    }
    
    // MARK: - Personal Voice Support
    
    func requestPersonalVoiceAuthorization() {
        switch currentProvider {
        case .system:
            systemTTSManager.requestPersonalVoiceAuthorization()
        case .ollama:
            // Ollama doesn't support personal voice
            break
        }
    }
    
    func checkPersonalVoiceAuthorization() {
        switch currentProvider {
        case .system:
            systemTTSManager.checkPersonalVoiceAuthorization()
        case .ollama:
            // Ollama doesn't support personal voice
            break
        }
    }
    
    // MARK: - SSML Support
    
    func setSSMLEnabled(_ enabled: Bool) {
        switch currentProvider {
        case .system:
            systemTTSManager.setSSMLEnabled(enabled)
        case .ollama:
            // Ollama doesn't support SSML
            break
        }
    }
}
