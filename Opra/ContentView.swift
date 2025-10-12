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
    
    // Computed property for button image
    private var buttonImageName: String {
        if ttsProviderManager.isSpeaking {
            return ttsProviderManager.isPaused ? "play.fill" : "pause.fill"
        } else {
            return "play.fill"
        }
    }
    
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
                
                Button("Settings") {
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
                            Image(systemName: buttonImageName)
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
                .frame(minWidth: 600, minHeight: 500)
                .frame(maxWidth: 800, maxHeight: 700)
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

#Preview {
    ContentView()
}

