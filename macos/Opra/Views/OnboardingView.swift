//
//  OnboardingView.swift
//  Opra
//
//  First-launch setup guide: welcome → choose a voice method (on-device Kokoro is the
//  recommended default) → optionally download the Kokoro model → finish. Shown until
//  SettingsManager.hasCompletedOnboarding is set.
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var tts: TTSProviderManager
    var onAddPDF: () -> Void
    var onFinish: () -> Void

    @State private var step = 0
    @State private var selectedProvider: TTSProvider = KokoroTTSManager.isSupported ? .kokoro : .system

    private let lastStep = 2

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)

            Divider()
            footer.padding(20)
        }
        .frame(width: 600, height: 500)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: voiceStep
        default: finishStep
        }
    }

    // MARK: - Steps
    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Welcome to Opra").font(.largeTitle).fontWeight(.bold)
            Text("Opra turns your PDFs into a hands-free listening experience with natural voices.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                featureRow("books.vertical", "Organize PDFs into a searchable library and folders")
                featureRow("text.bubble", "Follow along with a passage-by-passage reading script")
                featureRow("cpu", "Read fully offline with the on-device Kokoro voice")
            }
            .padding(.top, 8)
        }
    }

    private var voiceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose your voice").font(.title).fontWeight(.bold)
                Text("You can change this any time in Settings.").foregroundStyle(.secondary)
            }
            ForEach(TTSProvider.allCases) { provider in
                onboardingCard(provider)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var finishStep: some View {
        VStack(spacing: 18) {
            if selectedProvider == .kokoro && KokoroTTSManager.isSupported {
                Image(systemName: "cpu").font(.system(size: 56)).foregroundStyle(.tint)
                Text("Set up on-device Kokoro").font(.title).fontWeight(.bold)
                kokoroDownload
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("You're all set").font(.title).fontWeight(.bold)
                Text("Add a PDF to start listening.").foregroundStyle(.secondary)
            }
            Button {
                finish()
                onAddPDF()
            } label: {
                Label("Add your first PDF", systemImage: "plus").frame(maxWidth: 260)
            }
            .controlSize(.large).buttonStyle(.bordered)
        }
    }

    @ViewBuilder private var kokoroDownload: some View {
        switch tts.kokoroTTSManager.installState {
        case .notInstalled:
            Text("Download the Kokoro neural voice (~330 MB) to read offline with no API key.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Download Now") { tts.kokoroTTSManager.ensureModelInstalled() }
                .controlSize(.large).buttonStyle(.borderedProminent)
            Text("You can also download it later in Settings.").font(.caption).foregroundStyle(.secondary)
        case .downloading(let p):
            ProgressView(value: p).frame(maxWidth: 320)
            Text("Downloading… \(Int(p * 100))%").font(.caption).foregroundStyle(.secondary)
        case .installed:
            Label("Kokoro voice ready", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Button("Retry") { tts.kokoroTTSManager.ensureModelInstalled() }.buttonStyle(.bordered)
        }
    }

    // MARK: - Footer
    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(.bordered)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { i in
                    Circle().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if step < lastStep {
                Button(step == 0 ? "Get Started" : "Continue") { step += 1 }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Start Reading") { finish() }.buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers
    private func finish() {
        settings.setHasCompletedOnboarding(true)
        tts.setProvider(selectedProvider)
        onFinish()
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 24)
            Text(text)
        }
    }

    private func onboardingCard(_ provider: TTSProvider) -> some View {
        let supported = provider != .kokoro || KokoroTTSManager.isSupported
        let isSelected = selectedProvider == provider
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(provider.rawValue).fontWeight(.semibold)
                    if provider == .kokoro {
                        Text("Recommended").font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                    }
                }
                Text(supported ? provider.description : "Requires an Apple Silicon Mac")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor.opacity(0.5) : .clear))
        .opacity(supported ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture { if supported { selectedProvider = provider } }
    }
}
