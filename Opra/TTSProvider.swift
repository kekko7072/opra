import Foundation
import AVFoundation

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
            ollamaTTSManager.speak(text)
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
    
    var speechRate: Float {
        switch currentProvider {
        case .system:
            return systemTTSManager.speechRate
        case .ollama:
            return ollamaTTSManager.speechRate
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
    
    var currentVoice: AVSpeechSynthesisVoice? {
        switch currentProvider {
        case .system:
            return systemTTSManager.currentVoice
        case .ollama:
            return nil // Ollama doesn't use system voices
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
}
