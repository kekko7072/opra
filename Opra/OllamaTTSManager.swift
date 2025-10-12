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
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.isAvailable = false
                    self?.errorMessage = "Ollama not available: \(error.localizedDescription)"
                    return
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["models"] as? [[String: Any]] {
                    
                    self?.isAvailable = true
                    self?.availableModels = models.compactMap { $0["name"] as? String }
                    self?.selectBestTTSModel()
                } else {
                    self?.isAvailable = false
                    self?.errorMessage = "Could not parse Ollama response"
                }
            }
        }.resume()
    }
    
    private func selectBestTTSModel() {
        // Priority order for TTS models
        let preferredModels = [
            "bark:latest",
            "bark",
            "tortoise-tts:latest",
            "tortoise-tts",
            "coqui-tts:latest",
            "coqui-tts"
        ]
        
        for model in preferredModels {
            if availableModels.contains(model) {
                selectedModel = model
                return
            }
        }
        
        // If no preferred model found, use the first available
        if !availableModels.isEmpty {
            selectedModel = availableModels.first ?? ""
        }
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
        guard let url = URL(string: "\(ollamaBaseURL)/api/generate") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": selectedModel,
            "prompt": text,
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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Ollama TTS Error: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            // Parse the response to extract audio data
            // Note: This is a simplified implementation
            // Real TTS models might return different formats
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