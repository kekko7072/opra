import Foundation
import AVFoundation

@MainActor
class OllamaTTSManager: NSObject, ObservableObject {
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
    
    private let ollamaBaseURL = "http://localhost:11434"
    private var audioPlayer: AVAudioPlayer?
    private var currentAudioData: Data?
    
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
        
        generateSpeech(text: text) { [weak self] audioData in
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
        // Only work with orpheus model
        if !selectedModel.contains("sematre/orpheus") {
            DispatchQueue.main.async {
                self.errorMessage = "Only sematre/orpheus:en model is supported. Please install it using 'ollama pull sematre/orpheus:en'."
                completion(nil)
            }
            return
        }
        
        // For sematre/orpheus:en, we'll try to use it as a TTS model
        // If it fails, we'll show an appropriate error message
        guard let url = URL(string: "\(ollamaBaseURL)/api/generate") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Different prompts for different model types
        let prompt: String
        if selectedModel.contains("sematre/orpheus") {
            // For sematre/orpheus:en, try a TTS-specific prompt
            prompt = "Convert the following text to speech: \(text)"
        } else {
            // For known TTS models, use the text directly
            prompt = text
        }
        
        let requestBody: [String: Any] = [
            "model": selectedModel,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.7,
                "top_p": 0.9
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(nil)
            return
        }
        
        // Capture a snapshot of selectedModel to avoid accessing a MainActor-isolated property from a Sendable closure
        let selectedModelSnapshot = self.selectedModel
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Ollama TTS Error: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            // Try to parse the response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responseText = json["response"] as? String {
                    
                    // If we get text back instead of audio, it means the model doesn't support TTS
                    if selectedModelSnapshot.contains("sematre/orpheus") {
                        DispatchQueue.main.async {
                            self?.errorMessage = "sematre/orpheus:en is a language model, not a TTS model. This app currently only supports orpheus for TTS functionality."
                            completion(nil)
                        }
                        return
                    }
                }
            } catch {
                // If parsing fails, assume it's audio data
            }
            
            // For now, we'll assume the data is audio
            // In a real implementation, you'd need to handle different audio formats
            completion(data)
        }.resume()
    }
    
    private func playAudio(_ audioData: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            isSpeaking = true
            isPaused = false
            currentAudioData = audioData
            
            // Start progress tracking
            startProgressTracking()
        } catch {
            errorMessage = "Failed to play audio: \(error.localizedDescription)"
        }
    }
    
    private func startProgressTracking() {
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
                
                let progress = player.currentTime / player.duration
                self.readingProgress = Double(progress)
            }
        }
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
        currentAudioData = nil
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
}

extension OllamaTTSManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isSpeaking = false
            isPaused = false
            readingProgress = 0.0
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            errorMessage = "Audio playback error: \(error?.localizedDescription ?? "Unknown error")"
            isSpeaking = false
            isPaused = false
        }
    }
}
