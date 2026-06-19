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
                .disabled((queueCount == 0 && !tts.isSpeaking) || isKokoroDownloading)
                Button { reader.next() } label: { Image(systemName: "forward.end.fill") }
                    .disabled(queueCount == 0)
            }
            .buttonStyle(.plain)
            .font(.title3)

            centerStatus
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

    // MARK: - Center status (passage progress, model download, or error)
    private var kokoroState: ModelInstallState? {
        tts.currentProvider == .kokoro ? tts.kokoroTTSManager.installState : nil
    }
    private var isKokoroDownloading: Bool {
        if case .downloading = kokoroState { return true }
        return false
    }

    @ViewBuilder private var centerStatus: some View {
        if tts.currentProvider == .kokoro, let state = kokoroState, state != .installed {
            VStack(spacing: 5) {
                switch state {
                case .downloading(let p):
                    ProgressView(value: p).tint(.accentColor)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                        Text("Downloading on-device voice… \(Int(p * 100))% — playback starts when it's ready")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                case .notInstalled:
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
                        Text("On-device voice not downloaded yet").font(.caption)
                        Button("Download") { tts.kokoroTTSManager.ensureModelInstalled() }
                            .controlSize(.small)
                    }
                case .failed(let message):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message).font(.caption).lineLimit(1)
                        Button("Retry") { tts.kokoroTTSManager.ensureModelInstalled() }
                            .controlSize(.small)
                    }
                case .installed:
                    EmptyView()
                }
            }
        } else if let error = tts.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        } else if tts.isProcessing {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                Text("Generating speech…").font(.caption).foregroundStyle(.secondary)
            }
        } else if reader.isLoading {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                Text("Preparing reading script…").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 5) {
                ProgressView(value: progress).tint(.accentColor)
                HStack {
                    Text("\(min(activeIndex + 1, max(queueCount, 1))) of \(queueCount) passages")
                    Spacer()
                    if let doc = reader.document { Text("Reading 1–\(doc.pageCount)") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
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
                ForEach(TTSProvider.allCases) { Text($0.shortName).tag($0) }
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
                                HStack(spacing: 8) {
                                    Text(voice.name)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(voice.language).font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .opacity(tts.currentVoice?.identifier == voice.identifier ? 1 : 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(height: 220)
            } else {
                Text("Open Settings to configure the \(tts.currentProvider.shortName) voice.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            Button("Open Settings…") { onShowSettings() }
        }
        .padding(16)
        .frame(width: 360)
    }
}
