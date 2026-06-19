//
//  ContentView.swift
//  Opra
//
//  Main window: a three-column layout (library · PDF reader · reading script) with a
//  top bar and a bottom transport bar. Library is persisted with SwiftData; the active
//  document and playback are driven through ReaderViewModel + TTSProviderManager.
//

import SwiftUI
import SwiftData
import AppKit
import TipKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LibraryDocument.dateAdded, order: .reverse) private var documents: [LibraryDocument]
    @Query private var folders: [LibraryFolder]

    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var ttsProviderManager: TTSProviderManager
    @StateObject private var reader: ReaderViewModel

    @State private var selection: UUID?
    @State private var searchText = ""
    @State private var showScript = true
    @State private var showingSettings = false
    @State private var showingImporter = false
    @State private var showingOnboarding = false
    @State private var isImporting = false

    init() {
        let tts = TTSProviderManager()
        _ttsProviderManager = StateObject(wrappedValue: tts)
        _reader = StateObject(wrappedValue: ReaderViewModel(tts: tts))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HSplitView {
                LibrarySidebarView(
                    documents: documents,
                    folders: folders,
                    selection: $selection,
                    searchText: $searchText,
                    activeDocID: reader.document?.id,
                    isReading: ttsProviderManager.isSpeaking,
                    isImporting: isImporting,
                    onAdd: { showingImporter = true },
                    onDelete: deleteDocument,
                    onCreateFolder: createFolder,
                    onRenameFolder: renameFolder,
                    onDeleteFolder: deleteFolder,
                    onMove: moveDocument
                )
                ReaderPaneView(
                    pdfDocument: reader.pdfDocument,
                    currentPage: $reader.currentViewerPage,
                    readingPageCount: reader.document?.pageCount ?? 0,
                    showScript: $showScript,
                    loadError: reader.loadError,
                    isPageHidden: reader.hiddenPages.contains(reader.currentViewerPage),
                    onToggleHidePage: { reader.togglePageHidden(reader.currentViewerPage) }
                )
                .frame(minWidth: 380)
                if showScript {
                    ReadingScriptView(
                        documentTitle: reader.document?.title ?? "",
                        passages: reader.queue,
                        removedPassages: reader.removedPassages,
                        activeIndex: reader.activeQueueIndex,
                        isReading: ttsProviderManager.isSpeaking,
                        isLoading: reader.isLoading,
                        onPlay: { reader.playFrom(passage: $0) },
                        onDelete: { reader.delete($0) },
                        onRestore: { reader.restore($0) },
                        onRestoreAll: { reader.restoreAllPassages() }
                    )
                }
            }
            Divider()
            TransportBarView(
                reader: reader,
                tts: ttsProviderManager,
                settings: settingsManager,
                onShowSettings: { showingSettings = true }
            )
        }
        .frame(minWidth: 1040, minHeight: 680)
        .onAppear {
            ttsProviderManager.setSettingsManager(settingsManager)
            _ = UpdaterController.shared   // start Sparkle updater at launch
            if settingsManager.hasCompletedOnboarding {
                OpraTips.configureIfNeeded()
            } else {
                showingOnboarding = true
            }
            FoldersTip.hasDocuments = !documents.isEmpty
        }
        .onChange(of: selection) { _, newID in
            if let doc = documents.first(where: { $0.id == newID }) {
                reader.open(doc)
                VoiceTip.documentOpened = true
            }
        }
        .onChange(of: documents.count) { _, count in
            FoldersTip.hasDocuments = count > 0
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(
                settings: settingsManager,
                tts: ttsProviderManager,
                onAddPDF: { showingImporter = true },
                onFinish: {
                    showingOnboarding = false
                    OpraTips.configureIfNeeded()
                }
            )
            .interactiveDismissDisabled()
        }
        .onChange(of: ttsProviderManager.currentChunkIndex) { _, _ in
            syncPageToActivePassage()
            reader.persistPosition()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView(settingsManager: settingsManager, ttsProviderManager: ttsProviderManager)
                .frame(minWidth: 620, minHeight: 520)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            ttsProviderManager.stopSpeaking()
            try? modelContext.save()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 22, height: 22)
            Text("Opra").font(.headline)
            if let title = reader.document?.title {
                Text("—").foregroundStyle(.secondary)
                Text(title).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape").font(.title3)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.leading, 80).padding(.trailing, 18).padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Actions
    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        isImporting = true
        Task {
            var imported: [DocumentImporter.ImportedPDF] = []
            for url in urls {
                if let pdf = try? await Task.detached(priority: .userInitiated, operation: {
                    try DocumentImporter.importFile(from: url)
                }).value {
                    imported.append(pdf)
                }
            }
            for pdf in imported {
                let doc = LibraryDocument(title: pdf.title, pageCount: pdf.pageCount,
                                         storedFileName: pdf.storedFileName, thumbnailData: pdf.thumbnailData)
                modelContext.insert(doc)
                if selection == nil { selection = doc.id }
            }
            try? modelContext.save()
            isImporting = false
        }
    }

    private func createFolder(_ name: String) {
        modelContext.insert(LibraryFolder(name: name))
        try? modelContext.save()
    }

    private func renameFolder(_ folder: LibraryFolder, _ name: String) {
        folder.name = name
        try? modelContext.save()
    }

    private func deleteFolder(_ folder: LibraryFolder) {
        modelContext.delete(folder)
        try? modelContext.save()
    }

    private func moveDocument(_ id: UUID, to folder: LibraryFolder?) {
        guard let doc = documents.first(where: { $0.id == id }) else { return }
        doc.folder = folder
        try? modelContext.save()
    }

    private func deleteDocument(_ doc: LibraryDocument) {
        if reader.document?.id == doc.id {
            reader.close()
            selection = nil
        }
        DocumentImporter.deleteStoredFile(for: doc)
        modelContext.delete(doc)
        try? modelContext.save()
    }

    private func syncPageToActivePassage() {
        guard ttsProviderManager.isSpeaking, let passage = reader.activePassage else { return }
        if reader.currentViewerPage != passage.pageNumber {
            reader.currentViewerPage = passage.pageNumber
        }
    }
}
