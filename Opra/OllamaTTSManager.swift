//
//  OllamaTTSManager.swift
//  Opra
//
//  Created by Francesco Vezzani on 12/10/25.
//

import Foundation
import AVFoundation

@MainActor
class OllamaTTSManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isAvailable: Bool = false
    @Published var isProcessing: Bool = false
    @Published var availableModels: [String] = []
    @Published var selectedModel: String = ""
    @Published var errorMessage: String?
    @Published var isSpeaking: Bool = false
    @Published var isPaused: Bool = false
    @Published var speechRate: Float = 1.0
    @Published var readingProgress: Double = 0.0
    @Published var isRetrying: Bool = false
    @Published var currentWordIndex: Int = 0
    @Published var totalWords: Int = 0
    @Published var elapsedTime: TimeInterval = 0.0
    
    private let ollamaBaseURL = "http://localhost:11434"
    private var audioPlayer: AVAudioPlayer?
    private var currentAudioData: Data?
    private var fullText: String = ""
    private var words: [String] = []
    private var elapsedTimeTimer: DispatchSourceTimer?
    private var playbackStartDate: Date?
    
    override init() {
        super.init()
        checkOllamaAvailability()
    }
    
    func checkOllamaAvailability() {
        guard let url = URL(string: "\(ollamaBaseURL)/api/tags") else {
            isAvailable = false
            errorMessage = "Invalid Ollama URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0 // Add timeout
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.isAvailable = false
                    if (error as NSError).code == NSURLErrorCannotConnectToHost {
                        self?.errorMessage = "Ollama is not running. Please install and start Ollama first."
                    } else if (error as NSError).code == NSURLErrorTimedOut {
                        self?.errorMessage = "Ollama connection timed out. Please check if Ollama is running."
                    } else {
                        self?.errorMessage = "Ollama not available: \(error.localizedDescription)"
                    }
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let models = json["models"] as? [[String: Any]] {
                            
                            self?.isAvailable = true
                            self?.errorMessage = nil
                            self?.availableModels = models.compactMap { $0["name"] as? String }
                            self?.selectBestTTSModel()
                        } else {
                            self?.isAvailable = false
                            self?.errorMessage = "Could not parse Ollama response"
                        }
                    } else {
                        self?.isAvailable = false
                        self?.errorMessage = "Ollama server returned status \(httpResponse.statusCode)"
                    }
                } else {
                    self?.isAvailable = false
                    self?.errorMessage = "Invalid response from Ollama server"
                }
            }
        }.resume()
    }
    
    private func selectBestTTSModel() {
        // Only look for orpheus model
        if availableModels.contains("sematre/orpheus:en") {
            selectedModel = "sematre/orpheus:en"
            return
        }
        
        // If orpheus not found, don't select any model
        selectedModel = ""
    }
    
    func speak(_ text: String) {
        guard isAvailable && !selectedModel.isEmpty else {
            errorMessage = "Ollama TTS not available or no model selected"
            return
        }
        
        isProcessing = true
        errorMessage = nil
        readingProgress = 0.0
        
        // Preprocess text to handle formulas and special characters
        let processedText = preprocessTextForTTS(text)
        
        // Set up word tracking
        fullText = processedText
        words = processedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        totalWords = words.count
        currentWordIndex = 0
        
        generateSpeech(text: processedText) { [weak self] audioData in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                if let audioData = audioData {
                    self?.playAudio(audioData)
                } else {
                    self?.errorMessage = "Failed to generate speech"
                }
            }
        }
    }
    
    private func generateSpeech(text: String, completion: @escaping (Data?) -> Void) {
        // Check if we have a valid TTS model
        guard !selectedModel.isEmpty else {
            DispatchQueue.main.async {
                self.errorMessage = "No TTS model selected"
                completion(nil)
            }
            return
        }
        
        // For now, we'll disable Ollama TTS since sematre/orpheus is a language model, not TTS
        // In a real implementation, you'd need a proper TTS model like bark, xtts, or similar
        DispatchQueue.main.async {
            self.errorMessage = "Ollama TTS is not yet fully implemented. sematre/orpheus is a language model, not a TTS model. Please use System TTS for now."
            completion(nil)
        }
        
        // TODO: Implement proper TTS model support
        // This would require installing a TTS model like:
        // - bark (text-to-speech)
        // - xtts (multilingual TTS)
        // - or similar TTS-specific models
    }
    
    private func playAudio(_ audioData: Data) {
        // Validate audio data before attempting to play
        guard !audioData.isEmpty else {
            errorMessage = "No audio data received from Ollama"
            isProcessing = false
            return
        }
        
        // Check if data looks like valid audio (basic validation)
        guard audioData.count > 100 else {
            errorMessage = "Audio data too small, may be invalid"
            isProcessing = false
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            
            // Additional validation after creating player
            guard audioPlayer?.duration ?? 0 > 0 else {
                errorMessage = "Invalid audio duration, cannot play"
                isProcessing = false
                return
            }
            
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            // Final check before playing
            guard audioPlayer?.play() == true else {
                errorMessage = "Failed to start audio playback"
                isProcessing = false
                return
            }
            
            isSpeaking = true
            isPaused = false
            currentAudioData = audioData
            playbackStartDate = Date()
            
            // Start progress tracking
            startProgressTracking()
            startElapsedTimeTracking()
        } catch {
            errorMessage = "Failed to play audio: \(error.localizedDescription)"
            isProcessing = false
        }
    }
    
    private func startProgressTracking() {
        var timeoutCounter = 0
        let maxTimeout = 100 // 10 seconds timeout
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else {
                    timer.invalidate()
                    return
                }
                
                if !player.isPlaying {
                    timer.invalidate()
                    return
                }
                
                // Check for timeout (audio stuck)
                timeoutCounter += 1
                if timeoutCounter > maxTimeout {
                    print("Audio player timeout detected, stopping playback")
                    self.stopSpeaking()
                    self.errorMessage = "Audio playback timed out"
                    timer.invalidate()
                    return
                }
                
                // Check for valid duration
                guard player.duration > 0 else {
                    print("Invalid audio duration detected, stopping playback")
                    self.stopSpeaking()
                    self.errorMessage = "Invalid audio duration"
                    timer.invalidate()
                    return
                }
                
                let progress = player.currentTime / player.duration
                self.readingProgress = Double(progress)
                
                // Update word index based on progress
                self.currentWordIndex = Int(progress * Double(self.totalWords))
            }
        }
    }
    
    private func startElapsedTimeTracking() {
        // Cancel any existing elapsed time timer
        elapsedTimeTimer?.cancel()
        elapsedTimeTimer = nil
        
        // Create a timer for elapsed time updates
        let queue = DispatchQueue(label: "ollama.elapsed.timer", qos: .userInitiated)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0) // Update every second
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            // Calculate elapsed time if we have a start date
            if let startDate = self.playbackStartDate {
                let elapsed = Date().timeIntervalSince(startDate)
                
                Task { @MainActor in
                    // Only update if we're still speaking and have a valid start date
                    if self.isSpeaking && self.playbackStartDate != nil {
                        self.elapsedTime = elapsed
                    }
                }
            }
        }
        elapsedTimeTimer = timer
        timer.resume()
    }
    
    func pauseSpeaking() {
        audioPlayer?.pause()
        isPaused = true
    }
    
    func resumeSpeaking() {
        audioPlayer?.play()
        isPaused = false
    }
    
    func stopSpeaking() {
        audioPlayer?.stop()
        isSpeaking = false
        isPaused = false
        readingProgress = 0.0
        currentWordIndex = 0
        elapsedTime = 0.0
        currentAudioData = nil
        playbackStartDate = nil
        
        // Cancel elapsed time timer
        stopElapsedTimeTracking()
    }
    
    private func stopElapsedTimeTracking() {
        elapsedTimeTimer?.cancel()
        elapsedTimeTimer = nil
    }
    
    func setSpeechRate(_ rate: Float) {
        speechRate = rate
        audioPlayer?.rate = rate
    }
    
    func setModel(_ model: String) {
        selectedModel = model
    }
    
    func retryConnection() {
        isRetrying = true
        errorMessage = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkOllamaAvailability()
            self.isRetrying = false
        }
    }
    
    func installModel(_ modelName: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(ollamaBaseURL)/api/pull") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "name": modelName
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(false)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if error == nil {
                    self.checkOllamaAvailability()
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    private func preprocessTextForTTS(_ text: String) -> String {
        var processedText = text
        
        // Handle LaTeX math delimiters more carefully to preserve content
        processedText = processedText.replacingOccurrences(of: "\\(", with: " (")
        processedText = processedText.replacingOccurrences(of: "\\)", with: ") ")
        processedText = processedText.replacingOccurrences(of: "\\[", with: " [")
        processedText = processedText.replacingOccurrences(of: "\\]", with: "] ")
        processedText = processedText.replacingOccurrences(of: "$$", with: " ")
        processedText = processedText.replacingOccurrences(of: "$", with: " ")
        
        // Handle common LaTeX commands
        processedText = processedText.replacingOccurrences(of: "\\frac{", with: " fraction ")
        processedText = processedText.replacingOccurrences(of: "\\sqrt{", with: " square root of ")
        processedText = processedText.replacingOccurrences(of: "\\sum", with: " sum ")
        processedText = processedText.replacingOccurrences(of: "\\int", with: " integral ")
        processedText = processedText.replacingOccurrences(of: "\\lim", with: " limit ")
        processedText = processedText.replacingOccurrences(of: "\\infty", with: " infinity ")
        processedText = processedText.replacingOccurrences(of: "\\alpha", with: " alpha ")
        processedText = processedText.replacingOccurrences(of: "\\beta", with: " beta ")
        processedText = processedText.replacingOccurrences(of: "\\gamma", with: " gamma ")
        processedText = processedText.replacingOccurrences(of: "\\delta", with: " delta ")
        processedText = processedText.replacingOccurrences(of: "\\epsilon", with: " epsilon ")
        processedText = processedText.replacingOccurrences(of: "\\theta", with: " theta ")
        processedText = processedText.replacingOccurrences(of: "\\lambda", with: " lambda ")
        processedText = processedText.replacingOccurrences(of: "\\mu", with: " mu ")
        processedText = processedText.replacingOccurrences(of: "\\pi", with: " pi ")
        processedText = processedText.replacingOccurrences(of: "\\sigma", with: " sigma ")
        processedText = processedText.replacingOccurrences(of: "\\tau", with: " tau ")
        processedText = processedText.replacingOccurrences(of: "\\phi", with: " phi ")
        processedText = processedText.replacingOccurrences(of: "\\omega", with: " omega ")
        
        // Handle mathematical operators
        processedText = processedText.replacingOccurrences(of: "\\times", with: " times ")
        processedText = processedText.replacingOccurrences(of: "\\div", with: " divided by ")
        processedText = processedText.replacingOccurrences(of: "\\pm", with: " plus or minus ")
        processedText = processedText.replacingOccurrences(of: "\\mp", with: " minus or plus ")
        processedText = processedText.replacingOccurrences(of: "\\leq", with: " less than or equal to ")
        processedText = processedText.replacingOccurrences(of: "\\geq", with: " greater than or equal to ")
        processedText = processedText.replacingOccurrences(of: "\\neq", with: " not equal to ")
        processedText = processedText.replacingOccurrences(of: "\\approx", with: " approximately equal to ")
        processedText = processedText.replacingOccurrences(of: "\\equiv", with: " equivalent to ")
        processedText = processedText.replacingOccurrences(of: "\\propto", with: " proportional to ")
        processedText = processedText.replacingOccurrences(of: "\\in", with: " in ")
        processedText = processedText.replacingOccurrences(of: "\\notin", with: " not in ")
        processedText = processedText.replacingOccurrences(of: "\\subset", with: " subset of ")
        processedText = processedText.replacingOccurrences(of: "\\supset", with: " superset of ")
        processedText = processedText.replacingOccurrences(of: "\\cup", with: " union ")
        processedText = processedText.replacingOccurrences(of: "\\cap", with: " intersection ")
        processedText = processedText.replacingOccurrences(of: "\\emptyset", with: " empty set ")
        processedText = processedText.replacingOccurrences(of: "\\forall", with: " for all ")
        processedText = processedText.replacingOccurrences(of: "\\exists", with: " there exists ")
        processedText = processedText.replacingOccurrences(of: "\\rightarrow", with: " implies ")
        processedText = processedText.replacingOccurrences(of: "\\leftarrow", with: " implied by ")
        processedText = processedText.replacingOccurrences(of: "\\leftrightarrow", with: " if and only if ")
        
        // Handle superscripts and subscripts
        processedText = processedText.replacingOccurrences(of: "^{", with: " to the power of ")
        processedText = processedText.replacingOccurrences(of: "_{", with: " sub ")
        processedText = processedText.replacingOccurrences(of: "}", with: " ")
        
        // Handle common mathematical symbols
        processedText = processedText.replacingOccurrences(of: "∑", with: " sum ")
        processedText = processedText.replacingOccurrences(of: "∏", with: " product ")
        processedText = processedText.replacingOccurrences(of: "∫", with: " integral ")
        processedText = processedText.replacingOccurrences(of: "√", with: " square root ")
        processedText = processedText.replacingOccurrences(of: "∞", with: " infinity ")
        processedText = processedText.replacingOccurrences(of: "α", with: " alpha ")
        processedText = processedText.replacingOccurrences(of: "β", with: " beta ")
        processedText = processedText.replacingOccurrences(of: "γ", with: " gamma ")
        processedText = processedText.replacingOccurrences(of: "δ", with: " delta ")
        processedText = processedText.replacingOccurrences(of: "ε", with: " epsilon ")
        processedText = processedText.replacingOccurrences(of: "θ", with: " theta ")
        processedText = processedText.replacingOccurrences(of: "λ", with: " lambda ")
        processedText = processedText.replacingOccurrences(of: "μ", with: " mu ")
        processedText = processedText.replacingOccurrences(of: "π", with: " pi ")
        processedText = processedText.replacingOccurrences(of: "σ", with: " sigma ")
        processedText = processedText.replacingOccurrences(of: "τ", with: " tau ")
        processedText = processedText.replacingOccurrences(of: "φ", with: " phi ")
        processedText = processedText.replacingOccurrences(of: "ω", with: " omega ")
        processedText = processedText.replacingOccurrences(of: "×", with: " times ")
        processedText = processedText.replacingOccurrences(of: "÷", with: " divided by ")
        processedText = processedText.replacingOccurrences(of: "±", with: " plus or minus ")
        processedText = processedText.replacingOccurrences(of: "≤", with: " less than or equal to ")
        processedText = processedText.replacingOccurrences(of: "≥", with: " greater than or equal to ")
        processedText = processedText.replacingOccurrences(of: "≠", with: " not equal to ")
        processedText = processedText.replacingOccurrences(of: "≈", with: " approximately equal to ")
        processedText = processedText.replacingOccurrences(of: "≡", with: " equivalent to ")
        processedText = processedText.replacingOccurrences(of: "∝", with: " proportional to ")
        processedText = processedText.replacingOccurrences(of: "∈", with: " in ")
        processedText = processedText.replacingOccurrences(of: "∉", with: " not in ")
        processedText = processedText.replacingOccurrences(of: "⊂", with: " subset of ")
        processedText = processedText.replacingOccurrences(of: "⊃", with: " superset of ")
        processedText = processedText.replacingOccurrences(of: "∪", with: " union ")
        processedText = processedText.replacingOccurrences(of: "∩", with: " intersection ")
        processedText = processedText.replacingOccurrences(of: "∅", with: " empty set ")
        processedText = processedText.replacingOccurrences(of: "∀", with: " for all ")
        processedText = processedText.replacingOccurrences(of: "∃", with: " there exists ")
        processedText = processedText.replacingOccurrences(of: "→", with: " implies ")
        processedText = processedText.replacingOccurrences(of: "←", with: " implied by ")
        processedText = processedText.replacingOccurrences(of: "↔", with: " if and only if ")
        
        // Clean up excessive whitespace but preserve word boundaries
        processedText = processedText.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        processedText = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return processedText
    }
}

// MARK: - AVAudioPlayerDelegate
extension OllamaTTSManager {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isSpeaking = false
            isPaused = false
            readingProgress = 0.0
            currentWordIndex = 0
            elapsedTime = 0.0
            playbackStartDate = nil
            
            // Cancel elapsed time timer
            stopElapsedTimeTracking()
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            errorMessage = "Audio playback error: \(error?.localizedDescription ?? "Unknown error")"
            isSpeaking = false
            isPaused = false
            elapsedTime = 0.0
            playbackStartDate = nil
            
            // Cancel elapsed time timer
            stopElapsedTimeTracking()
        }
    }
}
