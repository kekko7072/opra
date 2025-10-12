import Foundation
import AVFoundation

class SettingsManager: ObservableObject {
    @Published var speechRate: Float = 0.5
    @Published var selectedVoiceIdentifier: String = ""
    @Published var autoStartReading: Bool = false
    @Published var showPDFViewer: Bool = true
    
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadSettings()
    }
    
    func loadSettings() {
        speechRate = userDefaults.object(forKey: "speechRate") as? Float ?? 0.5
        selectedVoiceIdentifier = userDefaults.string(forKey: "selectedVoiceIdentifier") ?? ""
        autoStartReading = userDefaults.bool(forKey: "autoStartReading")
        showPDFViewer = userDefaults.bool(forKey: "showPDFViewer")
    }
    
    func saveSettings() {
        userDefaults.set(speechRate, forKey: "speechRate")
        userDefaults.set(selectedVoiceIdentifier, forKey: "selectedVoiceIdentifier")
        userDefaults.set(autoStartReading, forKey: "autoStartReading")
        userDefaults.set(showPDFViewer, forKey: "showPDFViewer")
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
    
    func getSelectedVoice() -> AVSpeechSynthesisVoice? {
        if selectedVoiceIdentifier.isEmpty {
            return AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en") })
        }
        return AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
    }
}