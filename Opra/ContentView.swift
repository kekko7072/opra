import SwiftUI
import PDFKit
import AVFoundation

struct ContentView: View {
    @StateObject private var pdfExtractor = PDFTextExtractor()
    @StateObject private var ttsProviderManager = TTSProviderManager()
    @StateObject private var settingsManager = SettingsManager()
    @State private var showingFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var showingVoicePicker = false
    @State private var showingSettings = false
    @State private var showingPageControls = false
    @State private var showingOllamaSetup = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar
            HStack {
                Button("Select PDF") {
                    showingFilePicker = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: .command)
                
                if let fileURL = selectedFileURL {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.red)
                        Text(fileURL.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Text("Pages: \(pdfExtractor.totalPages) total")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Page Controls") {
                        showingPageControls.toggle()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("PDF Reader")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                Button("TTS Settings") {
                    showingSettings = true
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(",", modifiers: .command)
                
                if ttsProviderManager.currentProvider == .ollama && !ttsProviderManager.ollamaTTSManager.isAvailable {
                    Button("Setup Ollama") {
                        showingOllamaSetup = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Page Selection Controls (collapsible)
            if showingPageControls && pdfExtractor.isReadyToRead {
                VStack(spacing: 12) {
                    HStack {
                        Text("Page Selection")
                            .font(.headline)
                        Spacer()
                        Button("Done") {
                            showingPageControls = false
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start Page")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Button("-") {
                                    pdfExtractor.setStartPage(max(1, pdfExtractor.startPage - 1))
                                }
                                .buttonStyle(.bordered)
                                .disabled(pdfExtractor.startPage <= 1)
                                
                                TextField("Start", value: $pdfExtractor.startPage, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .onChange(of: pdfExtractor.startPage) { _, newValue in
                                        pdfExtractor.setStartPage(newValue)
                                    }
                                    .onSubmit {
                                        pdfExtractor.updatePageRange()
                                    }
                                
                                Button("+") {
                                    pdfExtractor.setStartPage(min(pdfExtractor.totalPages, pdfExtractor.startPage + 1))
                                }
                                .buttonStyle(.bordered)
                                .disabled(pdfExtractor.startPage >= pdfExtractor.totalPages)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("End Page")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Button("-") {
                                    pdfExtractor.setEndPage(max(pdfExtractor.startPage, pdfExtractor.endPage - 1))
                                }
                                .buttonStyle(.bordered)
                                .disabled(pdfExtractor.endPage <= pdfExtractor.startPage)
                                
                                TextField("End", value: $pdfExtractor.endPage, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .onChange(of: pdfExtractor.endPage) { _, newValue in
                                        pdfExtractor.setEndPage(newValue)
                                    }
                                    .onSubmit {
                                        pdfExtractor.updatePageRange()
                                    }
                                
                                Button("+") {
                                    pdfExtractor.setEndPage(min(pdfExtractor.totalPages, pdfExtractor.endPage + 1))
                                }
                                .buttonStyle(.bordered)
                                .disabled(pdfExtractor.endPage >= pdfExtractor.totalPages)
                            }
                        }
                        
                        Spacer()
                        
                        Text("Reading pages \(pdfExtractor.startPage)-\(pdfExtractor.endPage)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button("Read All") {
                            pdfExtractor.setPageRange(start: 1, end: pdfExtractor.totalPages)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Start Reading") {
                            pdfExtractor.startReading()
                            if settingsManager.autoStartReading && !pdfExtractor.extractedText.isEmpty {
                                ttsProviderManager.speak(pdfExtractor.extractedText)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!pdfExtractor.isReadyToRead)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
            
            // Main PDF Viewer Area
            if pdfExtractor.isReadyToRead {
                if let pdfDocument = pdfExtractor.pdfDocumentForViewing {
                    PDFViewerView(pdfDocument: pdfDocument, currentPage: $pdfExtractor.currentPage, ttsProviderManager: ttsProviderManager)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Welcome/Instructions Area
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 80))
                        .foregroundColor(.secondary)
                    
                    Text("Select a PDF file to begin")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text("Press ⌘O or click 'Select PDF' to choose a file")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Audio Control Bar (Music app style)
            if pdfExtractor.isReadyToRead {
                VStack(spacing: 0) {
                    Divider()
                    
                    HStack(spacing: 20) {
                        // Play/Pause Button
                        Button(action: {
                            if ttsProviderManager.isSpeaking {
                                if ttsProviderManager.isPaused {
                                    ttsProviderManager.resumeSpeaking()
                                } else {
                                    ttsProviderManager.pauseSpeaking()
                                }
                            } else {
                                ttsProviderManager.speak(pdfExtractor.extractedText)
                            }
                        }) {
                            Image(systemName: ttsProviderManager.isSpeaking ? (ttsProviderManager.isPaused ? "play.fill" : "pause.fill") : "play.fill")
                                .font(.title2)
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 40, height: 40)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(20)
                        .keyboardShortcut(" ", modifiers: [])
                        
                        // Stop Button
                        Button("Stop") {
                            ttsProviderManager.stopSpeaking()
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("s", modifiers: .command)
                        
                        // Speed Control
                        VStack(spacing: 4) {
                            HStack {
                                Text("Speed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(ttsProviderManager.speechRate * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Slow")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Slider(value: Binding(
                                    get: { ttsProviderManager.speechRate },
                                    set: { ttsProviderManager.setSpeechRate($0) }
                                ), in: 0.1...1.0, step: 0.05)
                                
                                Text("Fast")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 200)
                        
                        // Voice Selection
                        Button(action: {
                            if ttsProviderManager.currentProvider == .system {
                                showingVoicePicker = true
                            } else {
                                showingOllamaSetup = true
                            }
                        }) {
                            HStack {
                                Image(systemName: ttsProviderManager.currentProvider == .system ? "person.wave.2.fill" : "brain.head.profile")
                                Text(ttsProviderManager.currentProvider == .system ? (ttsProviderManager.currentVoice?.name ?? "Voice") : "Ollama Model")
                                    .font(.subheadline)
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        // Status
                        if ttsProviderManager.isSpeaking {
                            HStack {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.green)
                                Text(ttsProviderManager.isPaused ? "Paused" : "Speaking...")
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("Ready")
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Progress indicator
                        if pdfExtractor.isProcessing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Processing...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if ttsProviderManager.isSpeaking {
                            VStack(spacing: 4) {
                                ProgressView(value: ttsProviderManager.readingProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .frame(width: 150)
                                
                                Text("\(Int(ttsProviderManager.readingProgress * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    if !isAccessing {
                        pdfExtractor.errorMessage = "Could not access the selected file. Please try again."
                        return
                    }
                    
                    selectedFileURL = url
                    pdfExtractor.extractText(from: url)
                }
            case .failure(let error):
                pdfExtractor.errorMessage = "Error selecting file: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showingVoicePicker) {
            VoicePickerView(ttsManager: ttsProviderManager.systemTTSManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settingsManager: settingsManager, ttsProviderManager: ttsProviderManager)
                .frame(minWidth: 600, minHeight: 500)
                .frame(maxWidth: 800, maxHeight: 700)
        }
        .sheet(isPresented: $showingOllamaSetup) {
            OllamaSetupView(ollamaTTSManager: ttsProviderManager.ollamaTTSManager)
        }
        .onAppear {
            ttsProviderManager.systemTTSManager.setSettingsManager(settingsManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            ttsProviderManager.stopSpeaking()
        }
    }
    
    private func clearAll() {
        ttsProviderManager.stopSpeaking()
        pdfExtractor.clearText()
        selectedFileURL = nil
        showingPageControls = false
    }
}

struct PDFViewerView: View {
    let pdfDocument: PDFDocument
    @Binding var currentPage: Int
    @ObservedObject var ttsProviderManager: TTSProviderManager
    @State private var pdfView = PDFView()
    @State private var readingMarker: CGRect = .zero
    @State private var markerVisible: Bool = false
    @State private var markerTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation controls
            HStack {
                Button("Previous") {
                    pdfView.goToPreviousPage(nil)
                    updateCurrentPage()
                }
                .buttonStyle(.bordered)
                .disabled(!pdfView.canGoToPreviousPage)
                
                Text("Page \(currentPage) of \(pdfDocument.pageCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 120)
                
                Button("Next") {
                    pdfView.goToNextPage(nil)
                    updateCurrentPage()
                }
                .buttonStyle(.bordered)
                .disabled(!pdfView.canGoToNextPage)
                
                Spacer()
                
                // Page jump
                HStack {
                    Text("Go to:")
                    TextField("Page", value: $currentPage, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onSubmit {
                            jumpToPage()
                        }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // PDF content with vertical scrolling
            ZStack {
                PDFViewRepresentable(pdfView: pdfView)
                    .onAppear {
                        setupPDFView()
                    }
                
                // Reading marker overlay
                if markerVisible {
                    Rectangle()
                        .fill(Color.yellow.opacity(0.3))
                        .frame(width: readingMarker.width, height: readingMarker.height)
                        .position(x: readingMarker.midX, y: readingMarker.midY)
                        .animation(.easeInOut(duration: 0.5), value: readingMarker)
                }
                
                // Progress indicator
                if ttsProviderManager.isSpeaking {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack {
                                ProgressView(value: ttsProviderManager.readingProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .frame(width: 200)
                                
                                if ttsProviderManager.currentProvider == .system {
                                    Text("\(Int(ttsProviderManager.readingProgress * 100))% - Word \(ttsProviderManager.systemTTSManager.currentWordIndex) of \(ttsProviderManager.systemTTSManager.totalWords)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(Int(ttsProviderManager.readingProgress * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .cornerRadius(8)
                            Spacer()
                        }
                        .padding()
                    }
                }
            }
        }
    }
    
    private func setupPDFView() {
        pdfView.document = pdfDocument
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.interpolationQuality = .high
        
        // Start marker tracking when speaking
        startMarkerTracking()
    }
    
    private func startMarkerTracking() {
        markerTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                if ttsProviderManager.isSpeaking {
                    updateReadingMarker()
                } else {
                    markerVisible = false
                }
            }
        }
    }
    
    private func updateReadingMarker() {
        // Calculate approximate position based on reading progress
        let progress = ttsProviderManager.readingProgress
        let totalHeight = pdfView.documentView?.frame.height ?? 1000
        let markerHeight: CGFloat = 20
        let markerY = totalHeight * progress - markerHeight / 2
        
        readingMarker = CGRect(
            x: 0,
            y: max(0, min(markerY, totalHeight - markerHeight)),
            width: pdfView.frame.width,
            height: markerHeight
        )
        
        markerVisible = true
        
        // Auto-scroll to keep marker visible
        if let scrollView = pdfView.enclosingScrollView {
            let visibleRect = scrollView.documentVisibleRect
            let markerRect = readingMarker
            
            if markerRect.minY < visibleRect.minY || markerRect.maxY > visibleRect.maxY {
                let targetY = max(0, markerRect.midY - visibleRect.height / 2)
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: targetY))
            }
        }
    }
    
    private func updateCurrentPage() {
        if let page = pdfView.currentPage {
            let pageIndex = pdfDocument.index(for: page)
            currentPage = pageIndex + 1
        }
    }
    
    private func jumpToPage() {
        let targetPage = max(1, min(currentPage, pdfDocument.pageCount))
        if let page = pdfDocument.page(at: targetPage - 1) {
            pdfView.go(to: page)
            currentPage = targetPage
        }
    }
}

struct PDFViewRepresentable: NSViewRepresentable {
    let pdfView: PDFView
    
    func makeNSView(context: Context) -> PDFView {
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        // No updates needed
    }
}

struct VoicePickerView: View {
    @ObservedObject var ttsManager: TextToSpeechManager
    @Environment(\.dismiss) private var dismiss
    @State private var previewingVoice: AVSpeechSynthesisVoice?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Select Voice")
                .font(.headline)
            
            List(ttsManager.availableVoices, id: \.identifier) { voice in
                HStack {
                    VStack(alignment: .leading) {
                        Text(voice.name)
                            .font(.headline)
                        Text(voice.language)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Button("Preview") {
                            previewingVoice = voice
                            ttsManager.previewVoice(voice)
                        }
                        .buttonStyle(.bordered)
                        .disabled(ttsManager.isSpeaking && previewingVoice?.identifier != voice.identifier)
                        
                        if voice.identifier == ttsManager.currentVoice?.identifier {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    ttsManager.setVoice(voice)
                }
            }
            
            HStack {
                if ttsManager.isSpeaking && previewingVoice != nil {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.green)
                        Text("Previewing \(previewingVoice?.name ?? "voice")...")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                Button("Stop Preview") {
                    ttsManager.stopSpeaking()
                    previewingVoice = nil
                }
                .buttonStyle(.bordered)
                .disabled(!ttsManager.isSpeaking)
                
                Button("Done") {
                    ttsManager.stopSpeaking()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 450, height: 400)
    }
}

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var ttsProviderManager: TTSProviderManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingVoicePicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                // TTS Provider Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text-to-Speech Provider")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Picker("TTS Provider", selection: $ttsProviderManager.currentProvider) {
                        ForEach(TTSProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: ttsProviderManager.currentProvider) { _, newProvider in
                        ttsProviderManager.setProvider(newProvider)
                    }
                    
                    Text(ttsProviderManager.currentProvider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Speech Rate
                VStack(alignment: .leading, spacing: 12) {
                    Text("Speech Rate")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Slow")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Slider(value: $settingsManager.speechRate, in: 0.1...1.0, step: 0.05)
                            .onChange(of: settingsManager.speechRate) { _, newValue in
                                settingsManager.setSpeechRate(newValue)
                                ttsProviderManager.setSpeechRate(newValue)
                            }
                        
                        Text("Fast")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Button("Preview Speed") {
                            ttsProviderManager.previewSpeed(settingsManager.speechRate)
                        }
                        .buttonStyle(.bordered)
                        .disabled(ttsProviderManager.isSpeaking)
                        
                        if ttsProviderManager.isSpeaking {
                            HStack {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.green)
                                Text("Previewing speed...")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    Text("\(Int(settingsManager.speechRate * 100))%")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Divider()
                
                // Voice Selection (only for System TTS)
                if ttsProviderManager.currentProvider == .system {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Voice")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ttsProviderManager.currentVoice?.name ?? "Default Voice")
                                    .font(.subheadline)
                                Text(ttsProviderManager.currentVoice?.language ?? "en-US")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Change Voice") {
                                showingVoicePicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                } else {
                    // Ollama Model Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ollama Model")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ttsProviderManager.ollamaTTSManager.selectedModel.isEmpty ? "No model selected" : ttsProviderManager.ollamaTTSManager.selectedModel)
                                    .font(.subheadline)
                                Text(ttsProviderManager.ollamaTTSManager.isAvailable ? "Ollama connected" : "Ollama not available")
                                    .font(.caption)
                                    .foregroundColor(ttsProviderManager.ollamaTTSManager.isAvailable ? .green : .red)
                            }
                            
                            Spacer()
                            
                            Button("Setup Ollama") {
                                // This will be handled by the main view
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                }
                
                Divider()
                
                // Preferences
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preferences")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Toggle("Auto-start reading after page selection", isOn: $settingsManager.autoStartReading)
                        .onChange(of: settingsManager.autoStartReading) { _, newValue in
                            settingsManager.setAutoStartReading(newValue)
                        }
                }
                }
            }
        }
        .padding(30)
        .sheet(isPresented: $showingVoicePicker) {
            VoicePickerView(ttsManager: ttsProviderManager.systemTTSManager)
        }
    }
}

struct OllamaSetupView: View {
    @ObservedObject var ollamaTTSManager: OllamaTTSManager
    @Environment(\.dismiss) private var dismiss
    @State private var isInstalling = false
    @State private var installationProgress = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ollama TTS Setup")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 15) {
                // Status
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: ollamaTTSManager.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(ollamaTTSManager.isAvailable ? .green : .red)
                        
                        Text(ollamaTTSManager.isAvailable ? "Ollama is running" : "Ollama is not available")
                            .font(.subheadline)
                    }
                    
                    if let error = ollamaTTSManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Divider()
                
                // Installation Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Installation Instructions")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Install Ollama:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text("Visit ollama.ai and download Ollama for macOS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("Open Documentation") {
                                if let url = URL(string: "https://ollama.ai") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Text("2. Start Ollama:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text("Run 'ollama serve' in Terminal or start the Ollama app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("Open Terminal") {
                                let script = "tell application \"Terminal\" to activate"
                                let appleScript = NSAppleScript(source: script)
                                appleScript?.executeAndReturnError(nil)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Text("3. Install TTS Models:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text("Run these commands in Terminal:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("Copy Commands") {
                                let commands = "ollama pull bark\nollama pull tortoise-tts\nollama pull coqui-tts"
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(commands, forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ollama pull bark")
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                            
                            Text("ollama pull tortoise-tts")
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                            
                            Text("ollama pull coqui-tts")
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Divider()
                
                // Available Models
                if !ollamaTTSManager.availableModels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Models")
                            .font(.headline)
                        
                        List(ollamaTTSManager.availableModels, id: \.self) { model in
                            HStack {
                                Text(model)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                if model == ollamaTTSManager.selectedModel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                ollamaTTSManager.setModel(model)
                            }
                        }
                        .frame(height: 150)
                    }
                }
                
                // Install Model
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install New Model")
                        .font(.headline)
                    
                    HStack {
                        TextField("Model name (e.g., bark)", text: .constant("bark"))
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Install") {
                            installModel("bark")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isInstalling)
                    }
                    
                    if isInstalling {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(installationProgress)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            HStack {
                Button("Refresh") {
                    ollamaTTSManager.checkOllamaAvailability()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 600, height: 500)
    }
    
    private func installModel(_ modelName: String) {
        isInstalling = true
        installationProgress = "Installing \(modelName)..."
        
        ollamaTTSManager.installModel(modelName) { success in
            DispatchQueue.main.async {
                isInstalling = false
                if success {
                    installationProgress = "\(modelName) installed successfully!"
                } else {
                    installationProgress = "Failed to install \(modelName)"
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

