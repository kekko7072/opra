import SwiftUI
import AVFoundation

struct MobileSettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var tts: TTSProviderManager
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var serverURL = ""
    @State private var connectionError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading") {
                    Toggle("Follow the spoken page", isOn: $settings.enableFollowText).onChange(of: settings.enableFollowText) { _, value in settings.setEnableFollowText(value) }
                    Toggle("Start reading when opening a PDF", isOn: $settings.autoStartReading).onChange(of: settings.autoStartReading) { _, value in settings.setAutoStartReading(value) }
                    Picker("Provider", selection: Binding(get: { tts.currentProvider }, set: { tts.setProvider($0) })) {
                        ForEach(TTSProvider.allCases) { Text($0.shortName).tag($0) }
                    }.disabled(tts.isExporting)
                }
                Section("System voices") {
                    Picker("Voice", selection: Binding(get: { settings.selectedVoiceIdentifier }, set: { id in
                        if id.isEmpty {
                            settings.selectedVoiceIdentifier = ""
                            settings.saveSettings()
                            if let voice = settings.getSelectedVoice() { tts.systemTTSManager.setVoice(voice) }
                        } else if let voice = AVSpeechSynthesisVoice(identifier: id) { settings.setVoice(voice); tts.systemTTSManager.setVoice(voice) }
                    })) {
                        Text("Default").tag("")
                        ForEach(tts.systemTTSManager.availableVoices, id: \.identifier) { voice in Text("\(voice.name) (\(voice.language))").tag(voice.identifier) }
                    }
                }
                Section("Kokoro • offline") {
                    Picker("Voice", selection: Binding(get: { tts.kokoroTTSManager.selectedVoice }, set: { tts.kokoroTTSManager.setVoice($0) })) {
                        ForEach(KokoroModelInstaller.voiceNames, id: \.self) { Text($0).tag($0) }
                    }
                    switch tts.kokoroTTSManager.installState {
                    case .notInstalled: Button("Download voice model (~330 MB)") { tts.kokoroTTSManager.ensureModelInstalled() }
                    case .downloading(let value):
                        ProgressView(value: value)
                        Button("Cancel download") { tts.kokoroTTSManager.cancelInstall() }
                    case .installed: Label("Model installed", systemImage: "checkmark.circle")
                    case .failed(let message):
                        Text(message).foregroundStyle(.red)
                        Button("Retry download") { tts.kokoroTTSManager.ensureModelInstalled() }
                    }
                    Text("Requires a physical device. Kokoro stops when the app leaves the foreground because its GPU cannot synthesize in the background. Export audio first for listening in another audio app.").font(.caption)
                }
                Section("OpenAI • cloud") {
                    SecureField("API key", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save API key in Keychain") { settings.setOpenAIAPIKey(apiKey); tts.openAITTSManager.refreshConfiguration(); apiKey = "" }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !settings.openAIAPIKey.isEmpty { Button("Remove saved key", role: .destructive) { settings.setOpenAIAPIKey(""); tts.openAITTSManager.refreshConfiguration() } }
                    Picker("Model", selection: Binding(get: { settings.openAITTSModel }, set: { settings.setOpenAITTSModel($0) })) {
                        ForEach(SettingsManager.openAITTSModels, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Voice", selection: Binding(get: { settings.openAITTSVoice }, set: { settings.setOpenAITTSVoice($0) })) {
                        ForEach(OpenAISpeechOptions.voices(for: settings.openAITTSModel), id: \.self) { Text($0).tag($0) }
                    }
                    Text("Text is sent to OpenAI. Your API account pays for usage.").font(.caption)
                }
                Section("Ollama • your Mac or server") {
                    TextField("http://your-mac.local:11434", text: $serverURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save server and check voices") {
                        guard let url = URL(string: serverURL), ["http", "https"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                            connectionError = "Enter an HTTP or HTTPS server URL without credentials, a query, or a fragment."; return
                        }
                        connectionError = nil
                        settings.ollamaServerURL = url.absoluteString
                        settings.saveSettings()
                        Task { await tts.ollamaTTSManager.refreshVoices() }
                    }
                    Picker("Voice", selection: Binding(get: { settings.ollamaTTSVoice }, set: { settings.setOllamaTTSVoice($0) })) {
                        ForEach(Array(Set(tts.ollamaTTSManager.availableVoices + [settings.ollamaTTSVoice])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    if let message = connectionError ?? tts.ollamaTTSManager.connectionMessage { Text(message).font(.caption) }
                    Text("Ollama must run on an Apple Silicon Mac reachable from this device. localhost refers to your iPhone, not your Mac. Use a trusted private network; HTTP sends text unencrypted. The desktop MCP endpoint is a separate, Mac-only connection.").font(.caption)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .onAppear { serverURL = settings.ollamaServerURL }
        }
    }
}
