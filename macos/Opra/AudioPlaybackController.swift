//
//  AudioPlaybackController.swift
//  Opra
//
//  Shared playback engine for providers that synthesize audio chunk-by-chunk and
//  play it through AVAudioPlayer (OpenAI cloud TTS and on-device Kokoro). It owns all
//  playback/progress/elapsed/document-advance state and the AVAudioPlayer; each
//  provider injects two closures:
//    - `split`:        document-chunk text -> ordered speech chunks
//    - `produceAudio`: async producer of encoded audio Data for one speech chunk
//                      (a network request for OpenAI, in-process inference for Kokoro)
//  This is the logic previously inlined in OpenAITTSManager, made provider-agnostic.
//

import Foundation
import AVFoundation

/// Error whose message is surfaced verbatim to the user via `errorMessage`.
struct TTSProduceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {

    // MARK: - Published playback state (mirrors the old OpenAITTSManager surface)
    @Published private(set) var isProcessing = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var readingProgress: Double = 0.0
    @Published private(set) var currentWordIndex: Int = 0
    @Published private(set) var totalWords: Int = 0
    @Published private(set) var elapsedTime: TimeInterval = 0.0
    @Published private(set) var speechRate: Float = 0.5

    /// Index of the speech chunk currently playing, summed across document chunks.
    @Published private(set) var globalChunkIndex: Int = 0

    /// Index of the active document chunk (= passage, in the reading-script model).
    /// Drives passage highlighting; 0 for a single non-chunked utterance.
    @Published private(set) var currentDocumentChunkIndex: Int = 0

    struct SpeechChunk {
        let text: String
        let startWordIndex: Int
        let wordCount: Int
    }

    // MARK: - Provider-injected behaviour
    /// Splits a document chunk's text into ordered speech chunks.
    var split: (String) -> [SpeechChunk] = { _ in [] }
    /// Produces encoded audio Data for a single speech chunk. Throws to surface an error.
    var produceAudio: ((SpeechChunk) async throws -> Data)?

    weak var settingsManager: SettingsManager?
    weak var pdfExtractor: PDFTextExtractor?

    // MARK: - Internals
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var elapsedTimeTimer: DispatchSourceTimer?
    private var playbackStartDate: Date?
    private var activeRunID = UUID()
    private var produceTask: Task<Void, Never>?

    private var speechChunks: [SpeechChunk] = []
    private var currentSpeechChunkIndex = 0
    private var completedChunkBase = 0   // chunks completed in previous document chunks

    private var isDocumentChunked = false
    private var documentChunks: [String] = []
    private var currentDocumentChunk = 0

    // MARK: - Public API
    func speak(_ text: String) {
        stop()
        isDocumentChunked = false
        documentChunks = []
        currentDocumentChunk = 0
        currentDocumentChunkIndex = 0
        completedChunkBase = 0
        prepareAndSpeak(text)
    }

    func speakChunked(_ texts: [String], startChunk: Int) {
        stop()
        guard !texts.isEmpty else {
            errorMessage = "No text available for speech."
            return
        }
        isDocumentChunked = true
        documentChunks = texts
        currentDocumentChunk = max(0, min(startChunk, texts.count - 1))
        currentDocumentChunkIndex = currentDocumentChunk
        completedChunkBase = 0
        pdfExtractor?.setCurrentChunk(currentDocumentChunk)
        prepareAndSpeak(documentChunks[currentDocumentChunk])
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        audioPlayer?.pause()
        isPaused = true
    }

    func resume() {
        guard isSpeaking, isPaused else { return }
        audioPlayer?.play()
        isPaused = false
    }

    func stop() {
        activeRunID = UUID()
        produceTask?.cancel()
        produceTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        stopElapsedTimeTracking()

        isProcessing = false
        isSpeaking = false
        isPaused = false
        readingProgress = 0.0
        currentWordIndex = 0
        globalChunkIndex = 0
        currentDocumentChunkIndex = 0
        elapsedTime = 0.0
        playbackStartDate = nil
        pdfExtractor?.clearCurrentWordHighlight()
    }

    func setRate(_ rate: Float) {
        speechRate = rate
        audioPlayer?.rate = Self.playbackRate(for: rate)
    }

    /// Surface a pre-flight error (e.g. provider not configured) without starting playback.
    func fail(_ message: String) {
        finishWithError(message)
    }

    static func playbackRate(for speechRate: Float) -> Float {
        max(0.5, min(2.0, speechRate * 2.0))
    }

    // MARK: - Run loop
    private func prepareAndSpeak(_ text: String) {
        activeRunID = UUID()
        speechChunks = split(text)
        currentSpeechChunkIndex = 0
        totalWords = speechChunks.reduce(0) { $0 + $1.wordCount }
        currentWordIndex = 0
        readingProgress = 0.0
        elapsedTime = 0.0
        errorMessage = nil
        isProcessing = true
        isSpeaking = false
        isPaused = false
        pdfExtractor?.clearCurrentWordHighlight()

        requestCurrentSpeechChunk(runID: activeRunID)
    }

    private func requestCurrentSpeechChunk(runID: UUID) {
        guard activeRunID == runID else { return }
        guard currentSpeechChunkIndex < speechChunks.count else {
            handleTextFinished(runID: runID)
            return
        }
        guard let produceAudio else {
            finishWithError("No audio producer configured.")
            return
        }

        let chunk = speechChunks[currentSpeechChunkIndex]
        globalChunkIndex = completedChunkBase + currentSpeechChunkIndex
        isProcessing = true

        produceTask = Task { @MainActor in
            do {
                let data = try await produceAudio(chunk)
                guard self.activeRunID == runID else { return }
                self.playAudio(data, runID: runID)
            } catch is CancellationError {
                return
            } catch {
                guard self.activeRunID == runID else { return }
                self.finishWithError(error.localizedDescription)
            }
        }
    }

    private func playAudio(_ audioData: Data, runID: UUID) {
        guard activeRunID == runID else { return }
        do {
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            player.enableRate = true
            player.rate = Self.playbackRate(for: speechRate)
            player.prepareToPlay()

            audioPlayer = player
            guard player.play() else {
                finishWithError("Could not start audio playback.")
                return
            }

            isProcessing = false
            isSpeaking = true
            isPaused = false
            playbackStartDate = playbackStartDate ?? Date()
            startPlaybackTracking()
            startElapsedTimeTracking()
        } catch {
            finishWithError("Could not play audio: \(error.localizedDescription)")
        }
    }

    private func handleAudioFinished(runID: UUID) {
        guard activeRunID == runID else { return }
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer = nil
        currentSpeechChunkIndex += 1
        requestCurrentSpeechChunk(runID: runID)
    }

    private func handleTextFinished(runID: UUID) {
        guard activeRunID == runID else { return }

        if isDocumentChunked, currentDocumentChunk + 1 < documentChunks.count {
            completedChunkBase += speechChunks.count
            currentDocumentChunk += 1
            currentDocumentChunkIndex = currentDocumentChunk
            pdfExtractor?.setCurrentChunk(currentDocumentChunk)
            prepareAndSpeak(documentChunks[currentDocumentChunk])
            return
        }

        isProcessing = false
        isSpeaking = false
        isPaused = false
        readingProgress = 1.0
        currentWordIndex = totalWords
        stopElapsedTimeTracking()
        playbackStartDate = nil
        pdfExtractor?.clearCurrentWordHighlight()
    }

    private func finishWithError(_ message: String) {
        errorMessage = message
        isProcessing = false
        isSpeaking = false
        isPaused = false
        readingProgress = 0.0
        currentWordIndex = 0
        stopElapsedTimeTracking()
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer = nil
    }

    // MARK: - Progress tracking
    private func startPlaybackTracking() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackProgress()
            }
        }
    }

    private func updatePlaybackProgress() {
        guard let player = audioPlayer, player.duration > 0,
              currentSpeechChunkIndex < speechChunks.count else { return }

        let chunk = speechChunks[currentSpeechChunkIndex]
        let chunkProgress = max(0.0, min(1.0, player.currentTime / player.duration))
        let wordOffset = min(chunk.wordCount, Int(chunkProgress * Double(chunk.wordCount)))
        currentWordIndex = min(totalWords, chunk.startWordIndex + wordOffset)
        readingProgress = totalWords == 0 ? 0.0 : min(1.0, Double(currentWordIndex) / Double(totalWords))

        if settingsManager?.enableFollowText == true {
            pdfExtractor?.updateCurrentWord(currentWordIndex)
        }
    }

    private func startElapsedTimeTracking() {
        guard elapsedTimeTimer == nil else { return }
        let queue = DispatchQueue(label: "opra.tts.elapsed.timer", qos: .userInitiated)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, self.isSpeaking, let startDate = self.playbackStartDate else { return }
                self.elapsedTime = Date().timeIntervalSince(startDate)
            }
        }
        elapsedTimeTimer = timer
        timer.resume()
    }

    private func stopElapsedTimeTracking() {
        elapsedTimeTimer?.cancel()
        elapsedTimeTimer = nil
    }

    // MARK: - AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            let runID = activeRunID
            if flag {
                handleAudioFinished(runID: runID)
            } else {
                finishWithError("Audio playback stopped before finishing.")
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            finishWithError("Audio playback error: \(error?.localizedDescription ?? "Unknown error")")
        }
    }
}
