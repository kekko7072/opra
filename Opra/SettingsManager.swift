import Foundation
import AVFoundation

class SettingsManager: ObservableObject {
    @Published var speechRate: Float = 0.5
    @Published var selectedVoiceIdentifier: String = ""
    @Published var autoStartReading: Bool = false
    @Published var showPDFViewer: Bool = true
    @Published var chunkSize: Int = 10000
    @Published var enableFollowText: Bool = false
    @Published var enableSSML: Bool = false
    
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadSettings()
    }
    
    func loadSettings() {
        speechRate = userDefaults.object(forKey: "speechRate") as? Float ?? 0.5
        selectedVoiceIdentifier = userDefaults.string(forKey: "selectedVoiceIdentifier") ?? ""
        autoStartReading = userDefaults.bool(forKey: "autoStartReading")
        showPDFViewer = userDefaults.bool(forKey: "showPDFViewer")
        chunkSize = userDefaults.object(forKey: "chunkSize") as? Int ?? 10000
        enableFollowText = userDefaults.bool(forKey: "enableFollowText")
        enableSSML = userDefaults.bool(forKey: "enableSSML")
    }
    
    func saveSettings() {
        userDefaults.set(speechRate, forKey: "speechRate")
        userDefaults.set(selectedVoiceIdentifier, forKey: "selectedVoiceIdentifier")
        userDefaults.set(autoStartReading, forKey: "autoStartReading")
        userDefaults.set(showPDFViewer, forKey: "showPDFViewer")
        userDefaults.set(chunkSize, forKey: "chunkSize")
        userDefaults.set(enableFollowText, forKey: "enableFollowText")
        userDefaults.set(enableSSML, forKey: "enableSSML")
    }
    
    func setSpeechRate(_ rate: Float) {
        speechRate = rate
        saveSettings()
    }
    
    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoiceIdentifier = voice.identifier
        saveSettings()
    }
    
    func setAutoStartReading(_ enabled: Bool) {
        autoStartReading = enabled
        saveSettings()
    }
    
    func setShowPDFViewer(_ enabled: Bool) {
        showPDFViewer = enabled
        saveSettings()
    }
    
    func setChunkSize(_ size: Int) {
        chunkSize = max(1000, min(size, 50000)) // Limit between 1k and 50k words
        saveSettings()
    }
    
    func setEnableFollowText(_ enabled: Bool) {
        enableFollowText = enabled
        saveSettings()
    }
    
    func setSSMLEnabled(_ enabled: Bool) {
        enableSSML = enabled
        saveSettings()
    }
    
    func getSelectedVoice() -> AVSpeechSynthesisVoice? {
        if selectedVoiceIdentifier.isEmpty {
            return AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en") })
        }
        return AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
    }
}