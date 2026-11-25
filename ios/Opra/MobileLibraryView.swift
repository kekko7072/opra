import SwiftUI
import SwiftData
import PDFKit
import AVFoundation
import UniformTypeIdentifiers

struct MobileLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \LibraryDocument.dateAdded, order: .reverse) private var documents: [LibraryDocument]
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]
    @StateObject private var settings = SettingsManager()
    @StateObject private var tts: TTSProviderManager
    @StateObject private var reader: ReaderViewModel
    @StateObject private var audio = MobileAudioSession()
    @State private var importing = false
    @State private var loading = false
    @State private var showSettings = false
    @State private var showReader = false
    @State private var newFolder = false
    @State private var folderName = ""
    @State private var renamingFolder: LibraryFolder?
    @State private var search = ""
    @State private var error: String?

    init() {
        let tts = TTSProviderManager()
        _tts = StateObject(wrappedValue: tts)
        _reader = StateObject(wrappedValue: ReaderViewModel(tts: tts))
    }

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Importing PDF…") }
                if documents.isEmpty {
                    ContentUnavailableView("Your reading library", systemImage: "books.vertical", description: Text("Import a PDF from Files to read or listen."))
                }
                documentSection("Unfiled", documents.filter { $0.folder == nil })
                ForEach(folders) { folder in
                    Section {
                        ForEach(filtered(documents.filter { $0.folder?.id == folder.id })) { doc in documentRow(doc) }
                    } header: {
                        HStack {
                            Text(folder.name)
                            Spacer()
                            Menu {
                                Button("Rename folder") { renamingFolder = folder; folderName = folder.name; newFolder = true }
                                Button("Delete folder", role: .destructive) { context.delete(folder); save() }
                            } label: { Image(systemName: "ellipsis.circle") }
                                .accessibilityLabel("Folder options for \(folder.name)")
                        }
                    }
                }
            }
            .navigationTitle("Opra")
            .searchable(text: $search)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { renamingFolder = nil; folderName = ""; newFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    Button { importing = true } label: { Label("Import PDF", systemImage: "plus") }.disabled(loading)
                }
            }
            .navigationDestination(isPresented: $showReader) { MobileReaderView(reader: reader, tts: tts, settings: settings) }
            .safeAreaInset(edge: .bottom) {
                if reader.document != nil && !showReader {
                    Button { showReader = true } label: {
                        Label(reader.document?.title ?? "Continue reading", systemImage: tts.isSpeaking ? "waveform" : "book")
                            .lineLimit(1).frame(maxWidth: .infinity).padding()
                    }.background(.regularMaterial)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .failure(let failure): error = failure.localizedDescription
            case .success(let urls): importFiles(urls)
            }
        }
        .onOpenURL { importFiles([$0]) }
        .sheet(isPresented: $showSettings) { MobileSettingsView(settings: settings, tts: tts) }
        .alert(renamingFolder == nil ? "New folder" : "Rename folder", isPresented: $newFolder) {
            TextField("Folder name", text: $folderName)
            Button("Save") {
                let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    if let renamingFolder { renamingFolder.name = name }
                    else { context.insert(LibraryFolder(name: name)) }
                    save()
                }
                renamingFolder = nil
                folderName = ""
            }
            Button("Cancel", role: .cancel) { folderName = "" }
        }
        .alert("Opra", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onAppear { tts.setSettingsManager(settings); audio.configure(reader: reader) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                reader.persistPosition(); save()
                // MLX GPU work cannot run in the iOS background. Cloud/System audio
                // can continue; Kokoro resumes when the user returns to the app.
                if tts.currentProvider == .kokoro { tts.stopSpeaking() }
            }
        }
        .onChange(of: tts.currentChunkIndex) { _, _ in
            if tts.isSpeaking { reader.persistPosition(); save() }
            if settings.enableFollowText, let passage = reader.activePassage { reader.currentViewerPage = passage.pageNumber }
            audio.updateNowPlaying()
        }
        .onChange(of: tts.isSpeaking) { _, _ in audio.updateNowPlaying() }
        .onChange(of: tts.isPaused) { _, _ in audio.updateNowPlaying() }
    }

    private func filtered(_ docs: [LibraryDocument]) -> [LibraryDocument] {
        docs.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }
    private func documentSection(_ title: String, _ docs: [LibraryDocument]) -> some View {
        Section(title) { ForEach(filtered(docs)) { documentRow($0) } }
    }
    private func documentRow(_ doc: LibraryDocument) -> some View {
        Button { reader.open(doc); showReader = true } label: {
            HStack {
                if let data = doc.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: 42, height: 58)
                } else { Image(systemName: "doc.richtext").frame(width: 42) }
                VStack(alignment: .leading) {
                    Text(doc.title).foregroundStyle(.primary)
                    Text("\(doc.pageCount) pages").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            Menu("Move to folder") {
                Button("Unfiled") { doc.folder = nil; save() }
                ForEach(folders) { folder in Button(folder.name) { doc.folder = folder; save() } }
            }
            Button("Delete PDF", role: .destructive) { delete(doc) }
        }
        .swipeActions { Button("Delete", role: .destructive) { delete(doc) } }
    }
    private func delete(_ doc: LibraryDocument) {
        if reader.document?.id == doc.id { reader.close() }
        DocumentImporter.deleteStoredFile(for: doc); context.delete(doc); save()
    }
    private func save() {
        do { try context.save() } catch { self.error = error.localizedDescription }
    }
    private func importFiles(_ urls: [URL]) {
        guard !loading else { return }
        loading = true
        Task {
            defer { loading = false }
            for url in urls {
                do {
                    let imported = try await Task.detached { try DocumentImporter.importFile(from: url) }.value
                    let doc = LibraryDocument(title: imported.title, pageCount: imported.pageCount, storedFileName: imported.storedFileName, thumbnailData: imported.thumbnailData)
                    context.insert(doc)
                    save()
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct MobileReaderView: View {
    @ObservedObject var reader: ReaderViewModel
    @ObservedObject var tts: TTSProviderManager
    @ObservedObject var settings: SettingsManager
    @State private var script = false
    @State private var exportedURL: URL?
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if let error = reader.loadError { ContentUnavailableView(error, systemImage: "exclamationmark.triangle") }
            else if script { passageList }
            else if let pdf = reader.pdfDocument {
                MobilePDFView(document: pdf, page: $reader.currentViewerPage, highlightedPage: settings.enableFollowText && tts.isSpeaking ? reader.activePassage?.pageNumber : nil)
            }
            if reader.isLoading { ProgressView("Preparing reading script…").padding() }
            if let error = tts.errorMessage { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
            if let error = tts.exportError { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
            if let exportedURL { ShareLink("Share audio", item: exportedURL).padding(8) }
            if tts.isExporting {
                HStack {
                    ProgressView(value: tts.exportProgress)
                    Button("Cancel export") { exportTask?.cancel() }
                }.padding()
            }
            transport.padding().background(.regularMaterial)
        }
        .navigationTitle(reader.document?.title ?? "Reader")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { script.toggle() } label: { Label(script ? "PDF" : "Reading script", systemImage: script ? "doc.richtext" : "list.bullet") }
                Menu {
                    Button(reader.hiddenPages.contains(reader.currentViewerPage) ? "Include current page" : "Skip current page") { reader.togglePageHidden(reader.currentViewerPage) }
                    Button("Export audio") {
                        exportedURL = nil
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Opra-\(UUID().uuidString).\(tts.exportFileExtension)")
                        exportTask = Task {
                            await tts.exportAudio(reader.queue.map(\.text), to: url)
                            if !Task.isCancelled && tts.exportError == nil && FileManager.default.fileExists(atPath: url.path) { exportedURL = url }
                        }
                    }.disabled(!tts.canExportAudio || tts.isExporting || reader.queue.isEmpty)
                } label: { Label("Reading options", systemImage: "ellipsis.circle") }
            }
        }
        .onDisappear { reader.persistPosition() }
        .onChange(of: reader.isLoading) { _, loading in
            if !loading && settings.autoStartReading { reader.playPause() }
        }
    }

    private var transport: some View {
        VStack(spacing: 12) {
            ProgressView(value: tts.readingProgress)
            HStack {
                Picker("Voice provider", selection: Binding(get: { tts.currentProvider }, set: { tts.setProvider($0) })) {
                    ForEach(TTSProvider.allCases) { Text($0.shortName).tag($0) }
                }.labelsHidden().disabled(tts.isExporting)
                Spacer()
                Text("Page \(reader.currentViewerPage) / \(reader.document?.pageCount ?? 0)").font(.caption)
            }
            HStack(spacing: 32) {
                Button { reader.previous() } label: { Label("Previous", systemImage: "backward.end.fill") }
                Button { reader.playPause() } label: { Label(tts.isSpeaking && !tts.isPaused ? "Pause" : "Play", systemImage: tts.isSpeaking && !tts.isPaused ? "pause.fill" : "play.fill") }.font(.title)
                Button { reader.next() } label: { Label("Next", systemImage: "forward.end.fill") }
                Button { reader.stop() } label: { Label("Stop", systemImage: "stop.fill") }
            }.labelStyle(.iconOnly).disabled(reader.queue.isEmpty || reader.isLoading)
            HStack {
                Image(systemName: "tortoise")
                Slider(value: $settings.speechRate, in: 0.1...1, step: 0.05)
                    .onChange(of: settings.speechRate) { _, value in settings.setSpeechRate(value); tts.setSpeechRate(value) }
                Image(systemName: "hare")
            }
        }
    }
    private var passageList: some View {
        List {
            Section("Reading script") {
                ForEach(reader.queue) { passage in
                    Button { reader.playFrom(passage: passage) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Page \(passage.pageNumber)").font(.caption).foregroundStyle(.secondary)
                            Text(passage.text).foregroundStyle(.primary)
                        }
                    }
                    .listRowBackground(tts.isSpeaking && reader.activePassage?.id == passage.id ? Color.accentColor.opacity(0.15) : Color.clear)
                    .swipeActions { Button("Remove", role: .destructive) { reader.delete(passage) } }
                }
            }
            if !reader.removedPassages.isEmpty {
                Section("Removed passages") {
                    Button("Restore all") { reader.restoreAllPassages() }
                    ForEach(reader.removedPassages) { passage in
                        Button("Restore page \(passage.pageNumber)") { reader.restore(passage) }
                    }
                }
            }
        }
    }
}

struct MobilePDFView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int
    let highlightedPage: Int?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak view, weak coordinator = context.coordinator] _ in
            guard let view, let current = view.currentPage, let document = view.document else { return }
            let number = document.index(for: current) + 1
            DispatchQueue.main.async { coordinator?.parent.page = number }
        }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if view.document !== document { view.document = document }
        if let target = document.page(at: page - 1), view.currentPage !== target { view.go(to: target) }
        if let highlightedPage, let target = document.page(at: highlightedPage - 1), let selection = target.selection(for: target.bounds(for: .mediaBox)) {
            selection.color = UIColor.systemYellow.withAlphaComponent(0.25)
            view.highlightedSelections = [selection]
        } else { view.highlightedSelections = nil }
    }
    final class Coordinator {
        var parent: MobilePDFView
        var observer: NSObjectProtocol?
        init(_ parent: MobilePDFView) { self.parent = parent }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
