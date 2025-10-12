import Foundation
import PDFKit

class PDFTextExtractor: ObservableObject {
    @Published var extractedText: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var totalPages: Int = 0
    @Published var currentPage: Int = 1
    @Published var startPage: Int = 1
    @Published var endPage: Int = 1
    @Published var isReadyToRead: Bool = false
    @Published var isChunked: Bool = false
    @Published var currentChunk: Int = 0
    @Published var totalChunks: Int = 0
    @Published var chunkedTexts: [String] = []
    @Published var currentWordIndex: Int = 0
    @Published var highlightedWord: String = ""
    
    private var pdfDocument: PDFDocument?
    private var settingsManager: SettingsManager?
    private var extractionWorkItem: DispatchWorkItem?
    
    var pdfDocumentForViewing: PDFDocument? {
        return pdfDocument
    }
    
    func setSettingsManager(_ settings: SettingsManager) {
        settingsManager = settings
    }
    
    func extractText(from url: URL) {
        isProcessing = true
        errorMessage = nil
        extractedText = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Start accessing the security-scoped resource
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // Check if file exists and is readable
            guard FileManager.default.fileExists(atPath: url.path) else {
                DispatchQueue.main.async {
                    self.errorMessage = "File does not exist at the specified path"
                    self.isProcessing = false
                }
                return
            }
            
            // Check file permissions
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                DispatchQueue.main.async {
                    self.errorMessage = "File is not readable. Please check file permissions."
                    self.isProcessing = false
                }
                return
            }
            
            // Try to create PDFDocument
            guard let pdfDocument = PDFDocument(url: url) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Could not load PDF document. The file may be corrupted or not a valid PDF."
                    self.isProcessing = false
                }
                return
            }
            
            // Check if document has pages
            guard pdfDocument.pageCount > 0 else {
                DispatchQueue.main.async {
                    self.errorMessage = "PDF document has no pages"
                    self.isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.pdfDocument = pdfDocument
                self.totalPages = pdfDocument.pageCount
                self.startPage = 1
                self.endPage = pdfDocument.pageCount
                self.currentPage = 1
                self.isReadyToRead = true
            }
            
            self.extractTextFromPages()
        }
    }
    
    func extractTextFromPages() {
        guard let pdfDocument = pdfDocument else { return }
        
        // Cancel any pending extraction
        extractionWorkItem?.cancel()
        
        isProcessing = true
        errorMessage = nil
        extractedText = ""
        
        print("=== STARTING TEXT EXTRACTION ===")
        print("Page range: \(startPage)-\(endPage)")
        print("Current chunking state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        
        // Create a new work item with debouncing
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            var fullText = ""
            let startIndex = max(0, self.startPage - 1)
            let endIndex = min(pdfDocument.pageCount, self.endPage)
            
            print("Extracting pages \(startIndex + 1) to \(endIndex)")
            
            for pageIndex in startIndex..<endIndex {
                guard let page = pdfDocument.page(at: pageIndex) else { 
                    print("Warning: Could not access page \(pageIndex + 1)")
                    continue 
                }
                if let pageText = page.string {
                    print("Page \(pageIndex + 1): Extracted \(pageText.count) characters")
                    fullText += "--- Page \(pageIndex + 1) ---\n"
                    fullText += pageText + "\n\n"
                } else {
                    print("Warning: No text found on page \(pageIndex + 1)")
                }
            }
            
            DispatchQueue.main.async {
                print("Text extraction completed, processing...")
                self.processExtractedText(fullText)
                
                // Debug information
                print("Text extraction completed:")
                print("- Pages processed: \(startIndex + 1) to \(endIndex)")
                print("- Total characters: \(fullText.count)")
                print("- Total words: \(fullText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count)")
                print("- First 200 characters: \(String(fullText.prefix(200)))")
                if fullText.count > 200 {
                    print("- Last 200 characters: \(String(fullText.suffix(200)))")
                }
            }
        }
        
        extractionWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
    
    private func processExtractedText(_ text: String) {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordCount = words.count
        let chunkSize = settingsManager?.chunkSize ?? 10000
        
        print("=== PROCESSING EXTRACTED TEXT ===")
        print("Word count: \(wordCount)")
        print("Chunk size: \(chunkSize)")
        print("Current isChunked: \(isChunked)")
        print("Current totalChunks: \(totalChunks)")
        print("Pages: \(startPage)-\(endPage)")
        
        // Always process chunking for the current text selection
        // This ensures that when user selects a page range, we chunk that specific range
        if wordCount > chunkSize {
            // Text is too large, need to chunk it
            print("Text is large enough to chunk")
            isChunked = true
            chunkedTexts = createTextChunks(text: text, words: words, chunkSize: chunkSize)
            totalChunks = chunkedTexts.count
            currentChunk = 0
            extractedText = chunkedTexts.first ?? ""
            
            print("Text chunked into \(totalChunks) chunks of max \(chunkSize) words each")
            print("Ready for TTS: Pages \(startPage)-\(endPage), \(wordCount) words total")
            print("Final state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        } else if wordCount > 100 { // Only reset if we have substantial text
            // Text is small enough, no chunking needed
            print("Text is too small to chunk but substantial enough to reset state")
            isChunked = false
            chunkedTexts = []
            totalChunks = 0
            currentChunk = 0
            extractedText = text
            
            print("Text ready for TTS: Pages \(startPage)-\(endPage), \(wordCount) words (no chunking needed)")
            print("Final state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        } else {
            // Very small text - preserve existing chunking state
            print("Very small text extraction (\(wordCount) words) - preserving existing chunking state")
            if isChunked {
                extractedText = getCurrentChunkText()
                print("Preserved chunked state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
            } else {
                extractedText = text
                print("No existing chunking to preserve")
            }
        }
        
        isProcessing = false
        print("=== END PROCESSING EXTRACTED TEXT ===")
    }
    
    private func createTextChunks(text: String, words: [String], chunkSize: Int) -> [String] {
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentWordCount = 0
        
        for word in words {
            currentChunk.append(word)
            currentWordCount += 1
            
            if currentWordCount >= chunkSize {
                chunks.append(currentChunk.joined(separator: " "))
                currentChunk = []
                currentWordCount = 0
            }
        }
        
        // Add remaining words as the last chunk
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }
        
        return chunks
    }
    
    func nextChunk() {
        guard isChunked && currentChunk < totalChunks - 1 else { return }
        currentChunk += 1
        extractedText = chunkedTexts[currentChunk]
    }
    
    func previousChunk() {
        guard isChunked && currentChunk > 0 else { return }
        currentChunk -= 1
        extractedText = chunkedTexts[currentChunk]
    }
    
    func getCurrentChunkText() -> String {
        guard isChunked else { return extractedText }
        return chunkedTexts[currentChunk]
    }
    
    var chunkedTextsArray: [String] {
        return self.chunkedTexts
    }
    
    func setPageRange(start: Int, end: Int) {
        print("=== SET PAGE RANGE ===")
        print("Setting page range from \(start) to \(end)")
        print("Previous state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        
        let newStart = max(1, min(start, totalPages))
        let newEnd = max(newStart, min(end, totalPages))
        
        startPage = newStart
        endPage = newEnd
        currentPage = startPage
        
        // Force complete reset and re-extraction
        forceCompleteReset()
        
        print("=== END SET PAGE RANGE ===")
        
        // Force extraction for the new page range
        extractTextFromPages()
    }
    
    func setStartPage(_ page: Int) {
        print("=== SET START PAGE ===")
        print("Setting start page to \(page)")
        print("Previous state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        print("Current page range: \(startPage)-\(endPage)")
        
        let newStart = max(1, min(page, totalPages))
        startPage = newStart
        
        if endPage < startPage {
            endPage = startPage
        }
        
        currentPage = startPage
        
        print("New page range: \(startPage)-\(endPage)")
        
        // Force complete reset and re-extraction
        forceCompleteReset()
        
        print("=== END SET START PAGE ===")
        
        extractTextFromPages()
    }
    
    private func forceCompleteReset() {
        print("Force complete reset - clearing all state")
        
        // Cancel any pending work
        extractionWorkItem?.cancel()
        extractionWorkItem = nil
        
        // Reset all state
        isChunked = false
        chunkedTexts = []
        totalChunks = 0
        currentChunk = 0
        extractedText = ""
        isProcessing = false
        errorMessage = nil
        
        print("Reset complete - isChunked: \(isChunked), totalChunks: \(totalChunks)")
    }
    
    func setEndPage(_ page: Int) {
        print("=== SET END PAGE ===")
        print("Setting end page to \(page)")
        print("Previous state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        
        let newEnd = max(startPage, min(page, totalPages))
        endPage = newEnd
        
        // Reset chunking state when page range changes
        isChunked = false
        chunkedTexts = []
        totalChunks = 0
        currentChunk = 0
        
        print("Reset chunking state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        print("=== END SET END PAGE ===")
        
        extractTextFromPages()
    }
    
    func updatePageRange() {
        print("=== UPDATE PAGE RANGE ===")
        print("Updating page range")
        print("Previous state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        
        // Ensure start page is valid
        startPage = max(1, min(startPage, totalPages))
        
        // Ensure end page is valid and not before start page
        endPage = max(startPage, min(endPage, totalPages))
        
        // Update current page if needed
        if currentPage < startPage {
            currentPage = startPage
        } else if currentPage > endPage {
            currentPage = endPage
        }
        
        // Reset chunking state when page range changes
        isChunked = false
        chunkedTexts = []
        totalChunks = 0
        currentChunk = 0
        
        print("Reset chunking state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        print("=== END UPDATE PAGE RANGE ===")
        
        extractTextFromPages()
    }
    
    func clearText() {
        // Cancel any pending extraction
        extractionWorkItem?.cancel()
        extractionWorkItem = nil
        
        extractedText = ""
        errorMessage = nil
        totalPages = 0
        currentPage = 1
        startPage = 1
        endPage = 1
        isReadyToRead = false
        isChunked = false
        currentChunk = 0
        totalChunks = 0
        chunkedTexts = []
        pdfDocument = nil
    }
    
    func startReading() {
        if isReadyToRead {
            extractTextFromPages()
        }
    }
    
    func forceRechunk() {
        // Force re-chunking of the current text selection
        isChunked = false
        chunkedTexts = []
        totalChunks = 0
        currentChunk = 0
        extractTextFromPages()
    }
    
    func isReadyForTTS() -> Bool {
        return isReadyToRead && !extractedText.isEmpty && !isProcessing
    }
    
    func ensureChunkingForTTS() {
        print("=== ENSURING CHUNKING FOR TTS ===")
        print("Current state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        print("Extracted text length: \(extractedText.count) characters")
        
        if !isChunked && !extractedText.isEmpty {
            let words = extractedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let wordCount = words.count
            let chunkSize = settingsManager?.chunkSize ?? 10000
            
            print("Text not chunked, checking if needs chunking - \(wordCount) words, chunk size: \(chunkSize)")
            
            if wordCount > chunkSize {
                print("Text needs chunking, processing...")
                processExtractedText(extractedText)
            } else {
                print("Text doesn't need chunking")
            }
        } else if isChunked {
            print("Text is already chunked with \(totalChunks) chunks")
        } else {
            print("No text to chunk")
        }
        
        print("Final state - isChunked: \(isChunked), totalChunks: \(totalChunks)")
        print("=== END ENSURING CHUNKING FOR TTS ===")
    }
    
    func updateCurrentWord(_ wordIndex: Int) {
        currentWordIndex = wordIndex
        
        // Get the current text (either chunked or full text)
        let currentText = getCurrentChunkText()
        let words = currentText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        if wordIndex < words.count {
            highlightedWord = words[wordIndex]
        } else {
            highlightedWord = ""
        }
    }
    
    func getHighlightedText() -> AttributedString {
        let currentText = getCurrentChunkText()
        let words = currentText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        var attributedText = AttributedString(currentText)
        
        guard currentWordIndex < words.count else { return attributedText }
        
        // Find the current word in the text and highlight it
        let currentWord = words[currentWordIndex]
        let wordRange = attributedText.range(of: currentWord)
        
        if let range = wordRange {
            attributedText[range].backgroundColor = .blue
            attributedText[range].foregroundColor = .white
            attributedText[range].font = .system(.body, design: .monospaced).bold()
        }
        
        return attributedText
    }
}
