//
//  TransportBarView.swift
//  Opra
//
//  Bottom transport bar: prev/play-pause/next, passage progress, elapsed time, a
//  speed slider (shown as a percentage), and a voice chip that opens a quick
//  provider/voice picker.
//

import SwiftUI
import AVFoundation
import TipKit

struct TransportBarView: View {
    @ObservedObject var reader: ReaderViewModel
    @ObservedObject var tts: TTSProviderManager
    @ObservedObject var settings: SettingsManager
    var onShowSettings: () -> Void

    @State private var showingVoicePopover = false

    private var queueCount: Int { reader.queue.count }
    private var activeIndex: Int { reader.activeQueueIndex }
    private var progress: Double {
        guard queueCount > 0 else { return 0 }
        return Double(min(activeIndex + 1, queueCount)) / Double(queueCount)
    }

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 16) {
                Button { reader.previous() } label: { Image(systemName: "backward.end.fill") }
                    .disabled(queueCount == 0)
                Button { reader.playPause() } label: {
                    ZStack {
                        Circle().fill(Color.accentColor).frame(width: 52, height: 52)
                        Image(systemName: playIcon).font(.title2).foregroundStyle(.white)
                    }
                }
                .disabled(queueCount == 0 && !tts.isSpeaking)
                Button { reader.next() } label: { Image(systemName: "forward.end.fill") }
                    .disabled(queueCount == 0)
            }
            .buttonStyle(.plain)
            .font(.title3)

            VStack(spacing: 5) {
                ProgressView(value: progress).tint(.accentColor)
                HStack {
                    Text("\(min(activeIndex + 1, max(queueCount, 1))) of \(queueCount) passages")
                    Spacer()
                    if let doc = reader.document { Text("Reading 1–\(doc.pageCount)") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(formatTime(tts.elapsedTime)).monospacedDigit()
            }
            .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(settings.speechRate) },
                    set: { settings.setSpeechRate(Float($0)); tts.setSpeechRate(Float($0)) }
                ), in: 0.1...1.0)
                .frame(width: 110)
                Text("\(Int(settings.speechRate * 100))%")
                    .font(.caption).fontWeight(.medium).foregroundStyle(.tint).monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }

            Button { showingVoicePopover = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: voiceIcon)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(voiceTitle).font(.caption).fontWeight(.medium)
                        Text(voiceSubtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingVoicePopover, arrowEdge: .top) {
                VoiceQuickPicker(tts: tts, settings: settings) {
                    showingVoicePopover = false
                    onShowSettings()
                }
            }
            .popoverTip(VoiceTip(), arrowEdge: .top)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var playIcon: String {
        tts.isSpeaking ? (tts.isPaused ? "play.fill" : "pause.fill") : "play.fill"
    }
    private var voiceIcon: String {
        switch tts.currentProvider {
        case .system: return "mic"
        case .openAI: return "sparkles"
        case .kokoro: return "cpu"
        }
    }
    private var voiceTitle: String {
        switch tts.currentProvider {
        case .system: return tts.currentVoice?.name ?? "Default"
        case .openAI: return "OpenAI"
        case .kokoro: return "Kokoro"
        }
    }
    private var voiceSubtitle: String {
        switch tts.currentProvider {
        case .system: return tts.currentVoice?.language ?? "en-US"
        case .openAI: return settings.openAITTSVoice
        case .kokoro: return tts.kokoroTTSManager.selectedVoice
        }
    }
    private func formatTime(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

private struct VoiceQuickPicker: View {
    @ObservedObject var tts: TTSProviderManager
    @ObservedObject var settings: SettingsManager
    var onShowSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice").font(.headline)

            Picker("Provider", selection: Binding(
                get: { tts.currentProvider },
                set: { tts.setProvider($0) }
            )) {
                ForEach(TTSProvider.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tts.currentProvider == .system {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(tts.availableVoices, id: \.identifier) { voice in
                            Button {
                                tts.setVoice(voice)
                                settings.setVoice(voice)
                            } label: {
                                HStack {
                                    Text(voice.name)
                                    Spacer()
                                    Text(voice.language).font(.caption).foregroundStyle(.secondary)
                                    if tts.currentVoice?.identifier == voice.identifier {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(height: 200)
            } else {
                Text("Open Settings to configure the \(tts.currentProvider.rawValue) voice.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            Button("Open Settings…") { onShowSettings() }
        }
        .padding(16)
        .frame(width: 290)
    }
}
