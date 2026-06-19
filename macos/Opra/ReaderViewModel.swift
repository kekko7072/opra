//
//  ReaderViewModel.swift
//  Opra
//
//  The active reading session: resolves a LibraryDocument's bookmark, loads the PDF,
//  builds the passage list / reading queue, and drives playback through the TTS
//  facade. The active passage is read back from the engine's `currentChunkIndex`,
//  so highlighting works uniformly across System, OpenAI, and Kokoro.
//

import Foundation
import PDFKit
import Combine

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var document: LibraryDocument?
    @Published private(set) var pdfDocument: PDFDocument?
    @Published private(set) var allPassages: [Passage] = []
    @Published private(set) var deletedIDs: Set<Int> = []
    @Published var currentViewerPage: Int = 1
    @Published private(set) var loadError: String?

    let tts: TTSProviderManager
    private var accessingURL: URL?

    init(tts: TTSProviderManager) { self.tts = tts }

    /// Non-deleted passages, in order — the reading queue.
    var queue: [Passage] { allPassages.filter { !deletedIDs.contains($0.id) } }

    /// Index of the active passage within `queue` (mirrors the engine's chunk index).
    var activeQueueIndex: Int { min(tts.currentChunkIndex, max(0, queue.count - 1)) }

    var activePassage: Passage? {
        let q = queue
        guard q.indices.contains(activeQueueIndex) else { return nil }
        return q[activeQueueIndex]
    }

    // MARK: - Document lifecycle
    func open(_ doc: LibraryDocument) {
        stopAccessing()
        tts.stopSpeaking()
        loadError = nil
        document = doc
        deletedIDs = Set(doc.deletedPassageIDs)

        guard let resolved = DocumentImporter.resolveURL(from: doc.bookmarkData) else {
            loadError = "This file can't be found. It may have been moved or deleted."
            pdfDocument = nil
            allPassages = []
            return
        }
        if resolved.url.startAccessingSecurityScopedResource() { accessingURL = resolved.url }
        guard let pdf = PDFDocument(url: resolved.url), pdf.pageCount > 0 else {
            loadError = "Could not open this PDF."
            pdfDocument = nil
            allPassages = []
            return
        }
        pdfDocument = pdf
        allPassages = PassageSegmenter.passages(for: pdf)
        currentViewerPage = 1
        doc.lastOpened = Date()
    }

    func close() {
        tts.stopSpeaking()
        stopAccessing()
        document = nil
        pdfDocument = nil
        allPassages = []
        deletedIDs = []
    }

    private func stopAccessing() {
        accessingURL?.stopAccessingSecurityScopedResource()
        accessingURL = nil
    }

    // MARK: - Playback
    func playPause() {
        if tts.isSpeaking {
            if tts.isPaused { tts.resumeSpeaking() } else { tts.pauseSpeaking() }
        } else {
            play(from: clampedResumeIndex())
        }
    }

    func play(from index: Int) {
        let q = queue
        guard !q.isEmpty else { return }
        tts.speakChunkedText(q.map(\.text), startChunk: max(0, min(index, q.count - 1)))
    }

    func playFrom(passage: Passage) {
        if let idx = queue.firstIndex(where: { $0.id == passage.id }) { play(from: idx) }
    }

    func next() { play(from: activeQueueIndex + 1) }
    func previous() { play(from: activeQueueIndex - 1) }
    func stop() { tts.stopSpeaking() }

    // MARK: - Passage editing
    func delete(_ passage: Passage) {
        let wasSpeaking = tts.isSpeaking
        let resumeAt = activeQueueIndex
        deletedIDs.insert(passage.id)
        document?.deletedPassageIDs = Array(deletedIDs).sorted()
        if wasSpeaking { play(from: min(resumeAt, max(0, queue.count - 1))) }
    }

    func restoreAllPassages() {
        deletedIDs.removeAll()
        document?.deletedPassageIDs = []
    }

    // MARK: - Persistence
    /// Save the current position as the resume point.
    func persistPosition() {
        document?.lastPassageIndex = activeQueueIndex
    }

    private func clampedResumeIndex() -> Int {
        guard let doc = document else { return 0 }
        return max(0, min(doc.lastPassageIndex, max(0, queue.count - 1)))
    }
}
