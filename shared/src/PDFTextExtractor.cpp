#include "PDFTextExtractor.h"
#include <fstream>
#include <sstream>
#include <regex>
#include <algorithm>

#ifdef _WIN32
    // Windows-specific PDF handling
    #include <windows.h>
    // We'll use a Windows PDF library like PDFium or similar
#else
    // macOS/Linux PDF handling
    #include <CoreFoundation/CoreFoundation.h>
    #include <PDFKit/PDFKit.h>
#endif

namespace Opra {

class PDFTextExtractor::Impl {
public:
    Impl() = default;
    ~Impl() = default;
    
    ExtractionResult extractText(const std::string& filePath) {
        ExtractionResult result;
        result.success = false;
        
        // Check if file exists
        std::ifstream file(filePath);
        if (!file.good()) {
            result.errorMessage = "File does not exist or cannot be opened";
            return result;
        }
        file.close();
        
        // Get page count first
        int pageCount = getPageCount(filePath);
        if (pageCount <= 0) {
            result.errorMessage = "Could not determine page count or PDF is invalid";
            return result;
        }
        
        result.pageRange.totalPages = pageCount;
        result.pageRange.startPage = 1;
        result.pageRange.endPage = pageCount;
        
        // Extract text from all pages
        return extractTextFromPages(filePath, 1, pageCount);
    }
    
    ExtractionResult extractTextFromPages(const std::string& filePath, int startPage, int endPage) {
        ExtractionResult result;
        result.success = false;
        
        // Validate page range
        int pageCount = getPageCount(filePath);
        if (pageCount <= 0) {
            result.errorMessage = "Could not determine page count";
            return result;
        }
        
        startPage = std::max(1, startPage);
        endPage = std::min(pageCount, endPage);
        
        if (startPage > endPage) {
            result.errorMessage = "Invalid page range";
            return result;
        }
        
        result.pageRange.startPage = startPage;
        result.pageRange.endPage = endPage;
        result.pageRange.totalPages = pageCount;
        
        // Extract text using platform-specific implementation
        std::string extractedText = extractTextFromPDF(filePath, startPage, endPage);
        
        if (extractedText.empty()) {
            result.errorMessage = "No text could be extracted from the specified pages";
            return result;
        }
        
        // Clean the text
        result.fullText = cleanTextForTTS(extractedText);
        
        // Check if text needs chunking
        std::vector<std::string> words = splitIntoWords(result.fullText);
        int wordCount = words.size();
        int chunkSize = 10000; // Default chunk size
        
        if (wordCount > chunkSize) {
            result.isChunked = true;
            result.chunks = chunkText(result.fullText, chunkSize);
        } else {
            result.isChunked = false;
            TextChunk chunk;
            chunk.text = result.fullText;
            chunk.wordCount = wordCount;
            result.chunks.push_back(chunk);
        }
        
        result.success = true;
        return result;
    }
    
    std::vector<TextChunk> chunkText(const std::string& text, int chunkSize) {
        std::vector<TextChunk> chunks;
        std::vector<std::string> words = splitIntoWords(text);
        
        std::vector<std::string> currentChunk;
        int currentWordCount = 0;
        
        for (const auto& word : words) {
            currentChunk.push_back(word);
            currentWordCount++;
            
            if (currentWordCount >= chunkSize) {
                TextChunk chunk;
                chunk.text = joinWords(currentChunk);
                chunk.wordCount = currentWordCount;
                chunks.push_back(chunk);
                
                currentChunk.clear();
                currentWordCount = 0;
            }
        }
        
        // Add remaining words as the last chunk
        if (!currentChunk.empty()) {
            TextChunk chunk;
            chunk.text = joinWords(currentChunk);
            chunk.wordCount = currentWordCount;
            chunks.push_back(chunk);
        }
        
        return chunks;
    }
    
    int getPageCount(const std::string& filePath) {
        // Platform-specific implementation
#ifdef _WIN32
        return getPageCountWindows(filePath);
#else
        return getPageCountMacOS(filePath);
#endif
    }
    
    std::string cleanTextForTTS(const std::string& text) {
        std::string cleaned = text;
        
        // Remove control characters except newlines and tabs
        cleaned = std::regex_replace(cleaned, std::regex(R"([\x00-\x08\x0B\x0C\x0E-\x1F\x7F])"), "");
        
        // Remove zero-width characters
        cleaned = std::regex_replace(cleaned, std::regex(R"([\u200B-\u200D\u2060\uFEFF])"), "");
        
        // Replace problematic Unicode spaces with regular spaces
        cleaned = std::regex_replace(cleaned, std::regex(R"([\u00A0\u2000-\u200F\u2028-\u202F\u205F-\u206F\u3000])"), " ");
        
        // Handle LaTeX math delimiters
        cleaned = std::regex_replace(cleaned, std::regex(R"(\\\(|\\\)|\\\[|\\\]|\$\$|\$)"), " ");
        
        // Handle common LaTeX commands
        std::map<std::string, std::string> latexReplacements = {
            {"\\frac{", " fraction "},
            {"\\sqrt{", " square root of "},
            {"\\sum", " sum "},
            {"\\int", " integral "},
            {"\\lim", " limit "},
            {"\\infty", " infinity "},
            {"\\alpha", " alpha "},
            {"\\beta", " beta "},
            {"\\gamma", " gamma "},
            {"\\delta", " delta "},
            {"\\epsilon", " epsilon "},
            {"\\theta", " theta "},
            {"\\lambda", " lambda "},
            {"\\mu", " mu "},
            {"\\pi", " pi "},
            {"\\sigma", " sigma "},
            {"\\tau", " tau "},
            {"\\phi", " phi "},
            {"\\omega", " omega "},
            {"\\times", " times "},
            {"\\div", " divided by "},
            {"\\pm", " plus or minus "},
            {"\\leq", " less than or equal to "},
            {"\\geq", " greater than or equal to "},
            {"\\neq", " not equal to "},
            {"\\approx", " approximately equal to "},
            {"\\equiv", " equivalent to "},
            {"\\propto", " proportional to "},
            {"\\in", " in "},
            {"\\notin", " not in "},
            {"\\subset", " subset of "},
            {"\\supset", " superset of "},
            {"\\cup", " union "},
            {"\\cap", " intersection "},
            {"\\emptyset", " empty set "},
            {"\\forall", " for all "},
            {"\\exists", " there exists "},
            {"\\rightarrow", " implies "},
            {"\\leftarrow", " implied by "},
            {"\\leftrightarrow", " if and only if "},
            {"^{", " to the power of "},
            {"_{", " sub "},
            {"}", " "}
        };
        
        for (const auto& replacement : latexReplacements) {
            cleaned = std::regex_replace(cleaned, std::regex(replacement.first), replacement.second);
        }
        
        // Clean up multiple spaces
        cleaned = std::regex_replace(cleaned, std::regex(R"(\s{2,})"), " ");
        
        // Trim whitespace
        cleaned = trim(cleaned);
        
        return cleaned;
    }
    
private:
    std::string extractTextFromPDF(const std::string& filePath, int startPage, int endPage) {
#ifdef _WIN32
        return extractTextFromPDFWindows(filePath, startPage, endPage);
#else
        return extractTextFromPDFMacOS(filePath, startPage, endPage);
#endif
    }
    
#ifdef _WIN32
    int getPageCountWindows(const std::string& filePath);
    std::string extractTextFromPDFWindows(const std::string& filePath, int startPage, int endPage);
#else
    int getPageCountMacOS(const std::string& filePath);
    std::string extractTextFromPDFMacOS(const std::string& filePath, int startPage, int endPage);
#endif
    
    std::vector<std::string> splitIntoWords(const std::string& text) {
        std::vector<std::string> words;
        std::istringstream iss(text);
        std::string word;
        
        while (iss >> word) {
            if (!word.empty()) {
                words.push_back(word);
            }
        }
        
        return words;
    }
    
    std::string joinWords(const std::vector<std::string>& words) {
        std::ostringstream oss;
        for (size_t i = 0; i < words.size(); ++i) {
            if (i > 0) oss << " ";
            oss << words[i];
        }
        return oss.str();
    }
    
    std::string trim(const std::string& str) {
        size_t first = str.find_first_not_of(' ');
        if (first == std::string::npos) return "";
        size_t last = str.find_last_not_of(' ');
        return str.substr(first, (last - first + 1));
    }
};

// Constructor and destructor
PDFTextExtractor::PDFTextExtractor() : pImpl(std::make_unique<Impl>()) {}
PDFTextExtractor::~PDFTextExtractor() = default;

// Public method implementations
PDFTextExtractor::ExtractionResult PDFTextExtractor::extractText(const std::string& filePath) {
    return pImpl->extractText(filePath);
}

PDFTextExtractor::ExtractionResult PDFTextExtractor::extractTextFromPages(const std::string& filePath, int startPage, int endPage) {
    return pImpl->extractTextFromPages(filePath, startPage, endPage);
}

std::vector<PDFTextExtractor::TextChunk> PDFTextExtractor::chunkText(const std::string& text, int chunkSize) {
    return pImpl->chunkText(text, chunkSize);
}

int PDFTextExtractor::getPageCount(const std::string& filePath) {
    return pImpl->getPageCount(filePath);
}

std::string PDFTextExtractor::cleanTextForTTS(const std::string& text) {
    return pImpl->cleanTextForTTS(text);
}

} // namespace Opra