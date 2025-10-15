using iText.Kernel.Pdf;
using iText.Kernel.Pdf.Canvas.Parser;
using iText.Kernel.Pdf.Canvas.Parser.Listener;
using System.Text.RegularExpressions;

namespace Opra.Shared;

public class PDFTextExtractor
{
    public class PageRange
    {
        public int StartPage { get; set; }
        public int EndPage { get; set; }
        public int TotalPages { get; set; }
    }

    public class TextChunk
    {
        public string Text { get; set; } = string.Empty;
        public int WordCount { get; set; }
    }

    public class ExtractionResult
    {
        public bool Success { get; set; }
        public string ErrorMessage { get; set; } = string.Empty;
        public string FullText { get; set; } = string.Empty;
        public List<TextChunk> Chunks { get; set; } = new();
        public PageRange PageRange { get; set; } = new();
        public bool IsChunked { get; set; }
    }

    public ExtractionResult ExtractText(string filePath)
    {
        var result = new ExtractionResult();
        
        if (!File.Exists(filePath))
        {
            result.ErrorMessage = "File does not exist or cannot be opened";
            return result;
        }

        try
        {
            using var pdfReader = new PdfReader(filePath);
            using var pdfDocument = new PdfDocument(pdfReader);
            
            int pageCount = pdfDocument.GetNumberOfPages();
            if (pageCount <= 0)
            {
                result.ErrorMessage = "Could not determine page count or PDF is invalid";
                return result;
            }

            result.PageRange.TotalPages = pageCount;
            result.PageRange.StartPage = 1;
            result.PageRange.EndPage = pageCount;

            return ExtractTextFromPages(filePath, 1, pageCount);
        }
        catch (Exception ex)
        {
            result.ErrorMessage = $"Error reading PDF: {ex.Message}";
            return result;
        }
    }

    public ExtractionResult ExtractTextFromPages(string filePath, int startPage, int endPage)
    {
        var result = new ExtractionResult();
        
        try
        {
            using var pdfReader = new PdfReader(filePath);
            using var pdfDocument = new PdfDocument(pdfReader);
            
            int pageCount = pdfDocument.GetNumberOfPages();
            if (pageCount <= 0)
            {
                result.ErrorMessage = "Could not determine page count";
                return result;
            }

            startPage = Math.Max(1, startPage);
            endPage = Math.Min(pageCount, endPage);

            if (startPage > endPage)
            {
                result.ErrorMessage = "Invalid page range";
                return result;
            }

            result.PageRange.StartPage = startPage;
            result.PageRange.EndPage = endPage;
            result.PageRange.TotalPages = pageCount;

            var extractedText = ExtractTextFromPDF(pdfDocument, startPage, endPage);
            
            if (string.IsNullOrWhiteSpace(extractedText))
            {
                result.ErrorMessage = "No text could be extracted from the specified pages";
                return result;
            }

            result.FullText = CleanTextForTTS(extractedText);

            // Check if text needs chunking
            var words = SplitIntoWords(result.FullText);
            int wordCount = words.Count;
            int chunkSize = 10000; // Default chunk size

            if (wordCount > chunkSize)
            {
                result.IsChunked = true;
                result.Chunks = ChunkText(result.FullText, chunkSize);
            }
            else
            {
                result.IsChunked = false;
                result.Chunks.Add(new TextChunk
                {
                    Text = result.FullText,
                    WordCount = wordCount
                });
            }

            result.Success = true;
            return result;
        }
        catch (Exception ex)
        {
            result.ErrorMessage = $"Error extracting text: {ex.Message}";
            return result;
        }
    }

    public List<TextChunk> ChunkText(string text, int chunkSize = 10000)
    {
        var chunks = new List<TextChunk>();
        var words = SplitIntoWords(text);
        
        var currentChunk = new List<string>();
        int currentWordCount = 0;

        foreach (var word in words)
        {
            currentChunk.Add(word);
            currentWordCount++;

            if (currentWordCount >= chunkSize)
            {
                chunks.Add(new TextChunk
                {
                    Text = string.Join(" ", currentChunk),
                    WordCount = currentWordCount
                });
                
                currentChunk.Clear();
                currentWordCount = 0;
            }
        }

        // Add remaining words as the last chunk
        if (currentChunk.Count > 0)
        {
            chunks.Add(new TextChunk
            {
                Text = string.Join(" ", currentChunk),
                WordCount = currentWordCount
            });
        }

        return chunks;
    }

    public int GetPageCount(string filePath)
    {
        try
        {
            using var pdfReader = new PdfReader(filePath);
            using var pdfDocument = new PdfDocument(pdfReader);
            return pdfDocument.GetNumberOfPages();
        }
        catch
        {
            return 0;
        }
    }

    private string ExtractTextFromPDF(PdfDocument pdfDocument, int startPage, int endPage)
    {
        var fullText = new System.Text.StringBuilder();

        for (int i = startPage - 1; i < endPage; i++)
        {
            var page = pdfDocument.GetPage(i + 1);
            var strategy = new SimpleTextExtractionStrategy();
            var pageText = PdfTextExtractor.GetTextFromPage(page, strategy);
            
            if (!string.IsNullOrWhiteSpace(pageText))
            {
                fullText.AppendLine($"--- Page {i + 1} ---");
                fullText.AppendLine(pageText);
                fullText.AppendLine();
            }
        }

        return fullText.ToString();
    }

    private string CleanTextForTTS(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
            return "No content available for speech synthesis.";

        var cleaned = text;

        // Remove control characters except newlines and tabs
        cleaned = Regex.Replace(cleaned, @"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]", "");

        // Remove zero-width characters
        cleaned = Regex.Replace(cleaned, @"[\u200B-\u200D\u2060\uFEFF]", "");

        // Replace problematic Unicode spaces with regular spaces
        cleaned = Regex.Replace(cleaned, @"[\u00A0\u2000-\u200F\u2028-\u202F\u205F-\u206F\u3000]", " ");

        // Handle LaTeX math delimiters
        cleaned = Regex.Replace(cleaned, @"\\\(|\\\)|\\\[|\\\]|\$\$|\$", " ");

        // Handle common LaTeX commands
        var latexReplacements = new Dictionary<string, string>
        {
            {@"\\frac\{", " fraction "},
            {@"\\sqrt\{", " square root of "},
            {@"\\sum", " sum "},
            {@"\\int", " integral "},
            {@"\\lim", " limit "},
            {@"\\infty", " infinity "},
            {@"\\alpha", " alpha "},
            {@"\\beta", " beta "},
            {@"\\gamma", " gamma "},
            {@"\\delta", " delta "},
            {@"\\epsilon", " epsilon "},
            {@"\\theta", " theta "},
            {@"\\lambda", " lambda "},
            {@"\\mu", " mu "},
            {@"\\pi", " pi "},
            {@"\\sigma", " sigma "},
            {@"\\tau", " tau "},
            {@"\\phi", " phi "},
            {@"\\omega", " omega "},
            {@"\\times", " times "},
            {@"\\div", " divided by "},
            {@"\\pm", " plus or minus "},
            {@"\\leq", " less than or equal to "},
            {@"\\geq", " greater than or equal to "},
            {@"\\neq", " not equal to "},
            {@"\\approx", " approximately equal to "},
            {@"\\equiv", " equivalent to "},
            {@"\\propto", " proportional to "},
            {@"\\in", " in "},
            {@"\\notin", " not in "},
            {@"\\subset", " subset of "},
            {@"\\supset", " superset of "},
            {@"\\cup", " union "},
            {@"\\cap", " intersection "},
            {@"\\emptyset", " empty set "},
            {@"\\forall", " for all "},
            {@"\\exists", " there exists "},
            {@"\\rightarrow", " implies "},
            {@"\\leftarrow", " implied by "},
            {@"\\leftrightarrow", " if and only if "},
            {@"\^\{", " to the power of "},
            {@"_\{", " sub "},
            {@"\}", " "}
        };

        foreach (var replacement in latexReplacements)
        {
            cleaned = Regex.Replace(cleaned, replacement.Key, replacement.Value);
        }

        // Clean up multiple spaces
        cleaned = Regex.Replace(cleaned, @"\s{2,}", " ");

        // Trim whitespace
        cleaned = cleaned.Trim();

        return string.IsNullOrWhiteSpace(cleaned) ? "No content available for speech synthesis." : cleaned;
    }

    private List<string> SplitIntoWords(string text)
    {
        return text.Split(new[] { ' ', '\t', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries).ToList();
    }
}