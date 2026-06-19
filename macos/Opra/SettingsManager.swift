//
//  SettingsManager.swift
//  Opra
//
//  Created by Francesco Vezzani on 12/10/25.
//

import Foundation
import AVFoundation
import Security

class SettingsManager: ObservableObject {
    @Published var speechRate: Float = 0.5
    @Published var selectedVoiceIdentifier: String = ""
    @Published var autoStartReading: Bool = false
    @Published var showPDFViewer: Bool = true
    @Published var chunkSize: Int = 10000
    @Published var enableFollowText: Bool = false
    @Published var enableSSML: Bool = false
    @Published var openAIAPIKey: String = ""
    @Published var openAITTSModel: String = "gpt-4o-mini-tts"
    @Published var openAITTSVoice: String = "marin"
    @Published var openAITTSInstructions: String = "Read clearly with a natural, warm audiobook tone."
    @Published var hasCompletedOnboarding: Bool = false

    private let userDefaults = UserDefaults.standard
    private let openAIKeychainAccount = "openai_api_key"
    private var keychainService: String {
        Bundle.main.bundleIdentifier ?? "com.francescovezzani.Opra"
    }

    static let openAITTSModels = ["gpt-4o-mini-tts", "tts-1-hd", "tts-1"]
    static let openAITTSVoices = [
        "alloy", "ash", "ballad", "coral", "echo", "fable", "nova",
        "onyx", "sage", "shimmer", "verse", "marin", "cedar"
    ]

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
        openAIAPIKey = loadKeychainValue(account: openAIKeychainAccount) ?? ""
        openAITTSModel = userDefaults.string(forKey: "openAITTSModel") ?? "gpt-4o-mini-tts"
        openAITTSVoice = userDefaults.string(forKey: "openAITTSVoice") ?? "marin"
        openAITTSInstructions = userDefaults.string(forKey: "openAITTSInstructions") ?? "Read clearly with a natural, warm audiobook tone."
        hasCompletedOnboarding = userDefaults.bool(forKey: "hasCompletedOnboarding")
    }

    func saveSettings() {
        userDefaults.set(speechRate, forKey: "speechRate")
        userDefaults.set(selectedVoiceIdentifier, forKey: "selectedVoiceIdentifier")
        userDefaults.set(autoStartReading, forKey: "autoStartReading")
        userDefaults.set(showPDFViewer, forKey: "showPDFViewer")
        userDefaults.set(chunkSize, forKey: "chunkSize")
        userDefaults.set(enableFollowText, forKey: "enableFollowText")
        userDefaults.set(enableSSML, forKey: "enableSSML")
        userDefaults.set(openAITTSModel, forKey: "openAITTSModel")
        userDefaults.set(openAITTSVoice, forKey: "openAITTSVoice")
        userDefaults.set(openAITTSInstructions, forKey: "openAITTSInstructions")
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

    func setOpenAIAPIKey(_ key: String) {
        openAIAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        saveKeychainValue(openAIAPIKey, account: openAIKeychainAccount)
    }

    func setOpenAITTSModel(_ model: String) {
        openAITTSModel = model
        saveSettings()
    }

    func setOpenAITTSVoice(_ voice: String) {
        openAITTSVoice = voice
        saveSettings()
    }

    func setOpenAITTSInstructions(_ instructions: String) {
        openAITTSInstructions = instructions
        saveSettings()
    }

    func setHasCompletedOnboarding(_ done: Bool) {
        hasCompletedOnboarding = done
        userDefaults.set(done, forKey: "hasCompletedOnboarding")
    }

    func getSelectedVoice() -> AVSpeechSynthesisVoice? {
        if selectedVoiceIdentifier.isEmpty {
            return AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en") })
        }
        return AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
    }

    private func loadKeychainValue(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveKeychainValue(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]

        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
