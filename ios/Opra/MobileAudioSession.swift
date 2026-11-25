import AVFoundation
import MediaPlayer
import Combine
import UIKit

@MainActor
final class MobileAudioSession: ObservableObject {
    private weak var reader: ReaderViewModel?
    private var observers: [NSObjectProtocol] = []
    private var commands: [(MPRemoteCommand, Any)] = []

    func configure(reader: ReaderViewModel) {
        guard self.reader == nil else { return }
        self.reader = reader
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("Audio session configuration failed: \(error.localizedDescription)") }
        let center = MPRemoteCommandCenter.shared()
        add(center.playCommand) { reader in
            if reader.tts.isPaused { reader.tts.resumeSpeaking() }
            else if !reader.tts.isSpeaking { reader.playPause() }
        }
        add(center.pauseCommand) { $0.tts.pauseSpeaking() }
        add(center.togglePlayPauseCommand) { $0.playPause() }
        add(center.nextTrackCommand) { $0.next() }
        add(center.previousTrackCommand) { $0.previous() }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                if raw == AVAudioSession.InterruptionType.began.rawValue { self?.reader?.tts.pauseSpeaking() }
                // Resume only after a deliberate user action following an interruption.
                else { try? AVAudioSession.sharedInstance().setActive(true) }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.reader?.tts.pauseSpeaking() }
            }
        })
    }
    private func add(_ command: MPRemoteCommand, action: @escaping @MainActor (ReaderViewModel) -> Void) {
        let token = command.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let reader = self?.reader else { return }
                // Don't resume GPU synthesis from the lock screen.
                if reader.tts.currentProvider == .kokoro && UIApplication.shared.applicationState != .active { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                action(reader)
                self?.updateNowPlaying()
            }
            return .success
        }
        commands.append((command, token))
    }
    func updateNowPlaying() {
        guard let reader, let doc = reader.document else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: doc.title,
            MPMediaItemPropertyArtist: "Opra · Page \(reader.activePassage?.pageNumber ?? 1)",
            MPNowPlayingInfoPropertyPlaybackRate: reader.tts.isSpeaking && !reader.tts.isPaused ? 1.0 : 0.0
        ]
    }
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        commands.forEach { $0.0.removeTarget($0.1) }
    }
}
