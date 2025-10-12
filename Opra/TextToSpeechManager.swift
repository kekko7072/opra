import Foundation
import AVFoundation

class TextToSpeechManager: NSObject, ObservableObject {
    @Published var isSpeaking: Bool = false
    @Published var isPaused: Bool = false
    @Published var speechRate: Float = 0.5
    @Published var currentVoice: AVSpeechSynthesisVoice?
    @Published var readingProgress: Double = 0.0
    @Published var currentWordIndex: Int = 0
    @Published var totalWords: Int = 0
    
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var settingsManager: SettingsManager?
    private var fullText: String = ""
    private var words: [String] = []
    
    override init() {
        super.init()
        synthesizer.delegate = self
        setupDefaultVoice()
    }
    
    func setSettingsManager(_ settings: SettingsManager) {
        settingsManager = settings
        speechRate = settings.speechRate
        speechRate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, speechRate))
        if let voice = settings.getSelectedVoice() {
            currentVoice = voice
        }
    }
    
    private func setupDefaultVoice() {
        // Try to get a high-quality English voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            currentVoice = voice
        } else if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en") }) {
            currentVoice = voice
        } else {
            currentVoice = AVSpeechSynthesisVoice.speechVoices().first
        }
    }
    
    func speak(_ text: String) {
        stopSpeaking()
        
        fullText = text
        words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        totalWords = words.count
        currentWordIndex = 0
        readingProgress = 0.0
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = currentVoice
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, speechRate))
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        currentUtterance = utterance
        synthesizer.speak(utterance)
        
        // Start progress tracking
        startProgressTracking()
    }
    
    private func startProgressTracking() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if !self.isSpeaking {
                timer.invalidate()
                return
            }
            
            // Estimate progress based on time elapsed
            if let utterance = self.currentUtterance {
                let estimatedDuration = utterance.speechString.count / Int(self.speechRate * 200) // Rough estimation
                let elapsed = Date().timeIntervalSince(utterance.voice?.identifier == self.currentVoice?.identifier ? Date() : Date())
                let progress = min(1.0, max(0.0, elapsed / Double(estimatedDuration)))
                
                DispatchQueue.main.async {
                    self.readingProgress = progress
                    self.currentWordIndex = Int(progress * Double(self.totalWords))
                }
            }
        }
    }
    
    func pauseSpeaking() {
        if isSpeaking && !isPaused {
            synthesizer.pauseSpeaking(at: .immediate)
        }
    }
    
    func resumeSpeaking() {
        if isPaused {
            synthesizer.continueSpeaking()
        }
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
    }
    
    func setSpeechRate(_ rate: Float) {
        speechRate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        settingsManager?.setSpeechRate(speechRate)
        
        // Update current utterance if speaking
        if isSpeaking, let utterance = currentUtterance {
            utterance.rate = speechRate
        }
    }
    
    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        currentVoice = voice
        settingsManager?.setVoice(voice)
    }
    
    func previewVoice(_ voice: AVSpeechSynthesisVoice) {
        stopSpeaking()
        
        let previewText = "Hello, this is a preview of the \(voice.name) voice. How does it sound?"
        let utterance = AVSpeechUtterance(string: previewText)
        utterance.voice = voice
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, speechRate))
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }
    
    func previewSpeed(_ rate: Float) {
        stopSpeaking()
        
        let previewText = "This is a preview of the reading speed. How does this pace sound to you?"
        let utterance = AVSpeechUtterance(string: previewText)
        utterance.voice = currentVoice
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }
    
    nonisolated var availableVoices: [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
    }
}

@MainActor extension TextToSpeechManager: @MainActor AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        self.isSpeaking = true
        self.isPaused = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        self.isPaused = true
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        self.isPaused = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        self.isSpeaking = false
        self.isPaused = false
        self.currentUtterance = nil
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        self.isSpeaking = false
        self.isPaused = false
        self.currentUtterance = nil
    }
}
