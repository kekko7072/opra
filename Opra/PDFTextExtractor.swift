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
    
    private var pdfDocument: PDFDocument?
    
    var pdfDocumentForViewing: PDFDocument? {
        return pdfDocument
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
        
        isProcessing = true
        errorMessage = nil
        extractedText = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            var fullText = ""
            let startIndex = max(0, self.startPage - 1)
            let endIndex = min(pdfDocument.pageCount, self.endPage)
            
            for pageIndex in startIndex..<endIndex {
                guard let page = pdfDocument.page(at: pageIndex) else { continue }
                if let pageText = page.string {
                    fullText += "--- Page \(pageIndex + 1) ---\n"
                    fullText += pageText + "\n\n"
                }
            }
            
            DispatchQueue.main.async {
                self.extractedText = fullText
                self.isProcessing = false
            }
        }
    }
    
    func setPageRange(start: Int, end: Int) {
        let newStart = max(1, min(start, totalPages))
        let newEnd = max(newStart, min(end, totalPages))
        
        startPage = newStart
        endPage = newEnd
        currentPage = startPage
        extractTextFromPages()
    }
    
    func setStartPage(_ page: Int) {
        let newStart = max(1, min(page, totalPages))
        startPage = newStart
        
        if endPage < startPage {
            endPage = startPage
        }
        
        currentPage = startPage
        extractTextFromPages()
    }
    
    func setEndPage(_ page: Int) {
        let newEnd = max(startPage, min(page, totalPages))
        endPage = newEnd
        extractTextFromPages()
    }
    
    func updatePageRange() {
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
        
        extractTextFromPages()
    }
    
    func clearText() {
        extractedText = ""
        errorMessage = nil
        totalPages = 0
        currentPage = 1
        startPage = 1
        endPage = 1
        isReadyToRead = false
        pdfDocument = nil
    }
    
    func startReading() {
        if isReadyToRead {
            extractTextFromPages()
        }
    }
}
