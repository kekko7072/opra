//
//  SettingsView.swift
//  Opra
//
//  Multi-pane settings: General, Voices & Providers, and About. The provider picker
//  stays bound to TTSProviderManager.currentProvider; provider-specific config is
//  shown per selection.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var ttsProviderManager: TTSProviderManager
    @Environment(\.dismiss) private var dismiss

    @State private var pane: Pane = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general = "General"
        case voices = "Voices & Providers"
        case updates = "Updates"
        case about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .voices: return "person.wave.2"
            case .updates: return "arrow.down.circle"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(pane.rawValue).font(.title2).fontWeight(.bold)
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding(20)
                Divider()
                ScrollView { paneContent.padding(24) }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Pane.allCases) { p in
                Button { pane = p } label: {
                    Label(p.rawValue, systemImage: p.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(pane == p ? Color.accentColor.opacity(0.15) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var paneContent: some View {
        switch pane {
        case .general: GeneralPane(settingsManager: settingsManager, ttsProviderManager: ttsProviderManager)
        case .voices: VoicesPane(settingsManager: settingsManager, ttsProviderManager: ttsProviderManager)
        case .updates: UpdatesPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var ttsProviderManager: TTSProviderManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection("Reading speed") {
                HStack {
                    Text("Slow").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $settingsManager.speechRate, in: 0.1...1.0, step: 0.05)
                        .onChange(of: settingsManager.speechRate) { _, v in
                            settingsManager.setSpeechRate(v)
                            ttsProviderManager.setSpeechRate(v)
                        }
                    Text("Fast").font(.caption).foregroundStyle(.secondary)
                    Text("\(Int(settingsManager.speechRate * 100))%")
                        .font(.caption).foregroundStyle(.tint).monospacedDigit().frame(width: 40)
                }
                Button("Preview Speed") { ttsProviderManager.previewSpeed(settingsManager.speechRate) }
                    .buttonStyle(.bordered)
                    .disabled(ttsProviderManager.isSpeaking)
            }

            SettingsSection("Behavior") {
                Toggle("Auto-start reading when opening a document", isOn: Binding(
                    get: { settingsManager.autoStartReading },
                    set: { settingsManager.setAutoStartReading($0) }
                ))
                Toggle("Highlight the spoken passage", isOn: Binding(
                    get: { settingsManager.enableFollowText },
                    set: { settingsManager.setEnableFollowText($0) }
                ))
            }
        }
    }
}

// MARK: - Voices & Providers

private struct VoicesPane: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var ttsProviderManager: TTSProviderManager
    @State private var showingVoicePicker = false
    @State private var apiKeyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection("Text-to-Speech Provider") {
                ForEach(TTSProvider.allCases) { provider in
                    ProviderCard(provider: provider, isSelected: ttsProviderManager.currentProvider == provider)
                        .contentShape(Rectangle())
                        .onTapGesture { ttsProviderManager.setProvider(provider) }
                }
            }

            if ttsProviderManager.currentProvider == .system {
                systemConfig
            } else if ttsProviderManager.currentProvider == .openAI {
                openAIConfig
            } else if ttsProviderManager.currentProvider == .kokoro {
                KokoroConfig(manager: ttsProviderManager.kokoroTTSManager)
            }
        }
        .sheet(isPresented: $showingVoicePicker) {
            VoicePickerView(ttsManager: ttsProviderManager.systemTTSManager)
        }
        .onAppear { apiKeyDraft = settingsManager.openAIAPIKey }
    }

    private var systemConfig: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection("Voice") {
                HStack {
                    VStack(alignment: .leading) {
                        Text(ttsProviderManager.currentVoice?.name ?? "Default Voice").font(.subheadline)
                        Text(ttsProviderManager.currentVoice?.language ?? "en-US")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change Voice") { showingVoicePicker = true }.buttonStyle(.bordered)
                }
            }
            SettingsSection("Advanced") {
                HStack {
                    Text("Personal Voice")
                    Spacer()
                    if ttsProviderManager.isPersonalVoiceAuthorized {
                        Text("✓ Authorized").font(.caption).foregroundStyle(.green)
                    } else {
                        Button("Request Access") { ttsProviderManager.requestPersonalVoiceAuthorization() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Text("Status: \(ttsProviderManager.personalVoiceStatus)")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Use SSML markup (advanced)", isOn: Binding(
                    get: { settingsManager.enableSSML },
                    set: { settingsManager.setSSMLEnabled($0); ttsProviderManager.setSSMLEnabled($0) }
                ))
            }
        }
    }

    private var openAIConfig: some View {
        SettingsSection("OpenAI Configuration") {
            HStack {
                Text("API Key").frame(width: 70, alignment: .leading)
                SecureField("OpenAI API key", text: $apiKeyDraft).textFieldStyle(.roundedBorder)
                Button("Save") {
                    settingsManager.setOpenAIAPIKey(apiKeyDraft)
                    ttsProviderManager.openAITTSManager.refreshConfiguration()
                }.buttonStyle(.bordered)
                Button("Clear") {
                    apiKeyDraft = ""
                    settingsManager.setOpenAIAPIKey("")
                    ttsProviderManager.openAITTSManager.refreshConfiguration()
                }.buttonStyle(.bordered)
            }
            HStack {
                Text("Model").frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(
                    get: { settingsManager.openAITTSModel },
                    set: { settingsManager.setOpenAITTSModel($0) }
                )) { ForEach(SettingsManager.openAITTSModels, id: \.self) { Text($0).tag($0) } }
                .labelsHidden()
            }
            HStack {
                Text("Voice").frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(
                    get: { settingsManager.openAITTSVoice },
                    set: { settingsManager.setOpenAITTSVoice($0) }
                )) { ForEach(SettingsManager.openAITTSVoices, id: \.self) { Text($0).tag($0) } }
                .labelsHidden()
            }
            HStack(alignment: .top) {
                Text("Style").frame(width: 70, alignment: .leading)
                TextField("Voice instructions", text: Binding(
                    get: { settingsManager.openAITTSInstructions },
                    set: { settingsManager.setOpenAITTSInstructions($0) }
                ), axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
            }
            Text(settingsManager.openAIAPIKey.isEmpty ? "OpenAI TTS is not configured" : "OpenAI TTS is configured")
                .font(.caption).foregroundStyle(settingsManager.openAIAPIKey.isEmpty ? .orange : .green)
        }
    }
}

private struct ProviderCard: View {
    let provider: TTSProvider
    let isSelected: Bool

    private var badge: String {
        switch provider.kind {
        case .builtIn: return "Built-in"
        case .cloud: return "Cloud"
        case .onDevice: return "On-device"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(provider.rawValue).fontWeight(.semibold)
                    Text(badge).font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                Text(provider.description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear))
    }
}

private struct KokoroConfig: View {
    @ObservedObject var manager: KokoroTTSManager

    var body: some View {
        SettingsSection("On-Device Kokoro") {
            if !KokoroTTSManager.isSupported {
                Label("On-device Kokoro requires an Apple Silicon Mac.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                switch manager.installState {
                case .notInstalled:
                    Text("Download the Kokoro neural voice model (~330 MB) to read fully offline.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Download Model") { manager.ensureModelInstalled() }
                        .buttonStyle(.borderedProminent)
                case .downloading(let p):
                    ProgressView(value: p)
                    HStack {
                        Text("Downloading… \(Int(p * 100))%").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { manager.cancelInstall() }.controlSize(.small)
                    }
                case .installed:
                    Label("Model installed", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(.green)
                    HStack {
                        Text("Voice").frame(width: 70, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { manager.selectedVoice },
                            set: { manager.setVoice($0) }
                        )) {
                            ForEach(KokoroModelInstaller.voiceNames, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                    }
                    Button("Remove Model", role: .destructive) { manager.installer.remove() }
                        .controlSize(.small)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                    Button("Retry Download") { manager.ensureModelInstalled() }.buttonStyle(.bordered)
                }
            }
        }
    }
}

// MARK: - Updates (wired to Sparkle in Phase 7)

private struct UpdatesPane: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection("Software Updates") {
                HStack {
                    Text("Current version")
                    Spacer()
                    Text(version).foregroundStyle(.secondary)
                }
                Button("Check for Updates…") { UpdaterController.shared.checkForUpdates() }
                    .buttonStyle(.bordered)
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { UpdaterController.shared.automaticallyChecks },
                    set: { UpdaterController.shared.automaticallyChecks = $0 }
                ))
                Text("Opra updates itself directly using the Sparkle framework.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection("Opra") {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text("Opra").font(.title3).fontWeight(.semibold)
                        Text("Version \(version)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("GitHub") {
                        if let url = URL(string: "https://github.com/kekko7072/Opra") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(.bordered)
                }
                Text("A PDF reader that reads aloud with system, OpenAI, and on-device voices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsSection("Open-source components") {
                creditRow("Kokoro / kokoro-ios", "MIT — on-device neural TTS")
                creditRow("MLX Swift", "MIT — Apple machine-learning runtime")
                creditRow("Sparkle", "MIT — software updates")
            }
        }
    }

    private func creditRow(_ name: String, _ detail: String) -> some View {
        HStack {
            Text(name).font(.subheadline)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared section container

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
