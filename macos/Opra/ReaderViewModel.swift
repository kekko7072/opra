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
    @Published private(set) var hiddenPages: Set<Int> = []
    @Published var currentViewerPage: Int = 1
    @Published private(set) var loadError: String?
    /// True while the document's text is being extracted/segmented off the main thread.
    @Published private(set) var isLoading = false

    let tts: TTSProviderManager
    private var loadGeneration = 0

    init(tts: TTSProviderManager) { self.tts = tts }

    /// Passages to read: excludes individually deleted passages and passages on hidden pages.
    var queue: [Passage] {
        allPassages.filter { !deletedIDs.contains($0.id) && !hiddenPages.contains($0.pageNumber) }
    }

    /// Passages the user removed from the queue, in original document order, so they can be recovered.
    var removedPassages: [Passage] {
        allPassages.filter { deletedIDs.contains($0.id) }
    }

    /// Index of the active passage within `queue` (mirrors the engine's chunk index).
    var activeQueueIndex: Int { min(tts.currentChunkIndex, max(0, queue.count - 1)) }

    var activePassage: Passage? {
        let q = queue
        guard q.indices.contains(activeQueueIndex) else { return nil }
        return q[activeQueueIndex]
    }

    // MARK: - Document lifecycle
    func open(_ doc: LibraryDocument) {
        tts.stopSpeaking()
        loadError = nil
        document = doc
        deletedIDs = Set(doc.deletedPassageIDs)
        hiddenPages = Set(doc.hiddenPages)

        let url = DocumentImporter.fileURL(for: doc)
        guard FileManager.default.fileExists(atPath: url.path),
              let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
            loadError = "This document's file is missing. Try removing and re-adding it."
            pdfDocument = nil
            allPassages = []
            isLoading = false
            return
        }
        pdfDocument = pdf            // viewer renders immediately
        currentViewerPage = 1
        doc.lastOpened = Date()

        // Extract + segment passages off the main thread so the UI stays responsive
        // and can show a "Preparing…" indicator on large documents.
        loadGeneration += 1
        let generation = loadGeneration
        let docID = doc.id
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let passages = PassageSegmenter.passages(for: pdf)
            await MainActor.run {
                guard self.loadGeneration == generation, self.document?.id == docID else { return }
                self.allPassages = passages
                self.isLoading = false
            }
        }
    }

    func close() {
        tts.stopSpeaking()
        loadGeneration += 1
        isLoading = false
        document = nil
        pdfDocument = nil
        allPassages = []
        deletedIDs = []
        hiddenPages = []
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

    /// Hide (or unhide) a page so its passages aren't read.
    func togglePageHidden(_ page: Int) {
        let wasSpeaking = tts.isSpeaking
        let resumeAt = activeQueueIndex
        if hiddenPages.contains(page) { hiddenPages.remove(page) } else { hiddenPages.insert(page) }
        document?.hiddenPages = Array(hiddenPages).sorted()
        if wasSpeaking { play(from: min(resumeAt, max(0, queue.count - 1))) }
    }

    /// Bring a single removed passage back into the reading queue.
    func restore(_ passage: Passage) {
        let wasSpeaking = tts.isSpeaking
        let resumeAt = activeQueueIndex
        deletedIDs.remove(passage.id)
        document?.deletedPassageIDs = Array(deletedIDs).sorted()
        if wasSpeaking { play(from: min(resumeAt, max(0, queue.count - 1))) }
    }

    func restoreAllPassages() {
        let wasSpeaking = tts.isSpeaking
        let resumeAt = activeQueueIndex
        deletedIDs.removeAll()
        document?.deletedPassageIDs = []
        if wasSpeaking { play(from: min(resumeAt, max(0, queue.count - 1))) }
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
