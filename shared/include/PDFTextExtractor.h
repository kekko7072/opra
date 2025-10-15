#pragma once

#include <string>
#include <vector>
#include <memory>

namespace Opra {
    class PDFTextExtractor {
    public:
        struct PageRange {
            int startPage;
            int endPage;
            int totalPages;
        };
        
        struct TextChunk {
            std::string text;
            int wordCount;
        };
        
        struct ExtractionResult {
            bool success;
            std::string errorMessage;
            std::string fullText;
            std::vector<TextChunk> chunks;
            PageRange pageRange;
            bool isChunked;
        };
        
        PDFTextExtractor();
        ~PDFTextExtractor();
        
        // Extract text from PDF file
        ExtractionResult extractText(const std::string& filePath);
        
        // Extract text from specific page range
        ExtractionResult extractTextFromPages(const std::string& filePath, int startPage, int endPage);
        
        // Chunk text into smaller pieces
        std::vector<TextChunk> chunkText(const std::string& text, int chunkSize = 10000);
        
        // Get page count from PDF
        int getPageCount(const std::string& filePath);
        
        // Clean text for TTS
        std::string cleanTextForTTS(const std::string& text);
        
    private:
        class Impl;
        std::unique_ptr<Impl> pImpl;
    };
}