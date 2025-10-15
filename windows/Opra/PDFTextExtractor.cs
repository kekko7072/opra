using iText.Kernel.Pdf;
using iText.Kernel.Pdf.Canvas.Parser;
using iText.Kernel.Pdf.Canvas.Parser.Listener;
using System;

namespace Opra;

public class PDFTextExtractor
{
    public class PageRangeInfo
    {
        public int TotalPages { get; set; }
        public int StartPage { get; set; }
        public int EndPage { get; set; }
    }

    public class ExtractionResult
    {
        public bool Success { get; set; }
        public string FullText { get; set; } = string.Empty;
        public PageRangeInfo PageRange { get; set; } = new();
        public string ErrorMessage { get; set; } = string.Empty;
    }

    public ExtractionResult ExtractText(string filePath, int startPage = 1, int endPage = -1)
    {
        try
        {
            using var pdfReader = new PdfReader(filePath);
            using var pdfDocument = new PdfDocument(pdfReader);
            
            int pageCount = pdfDocument.GetNumberOfPages();
            int start = Math.Max(1, startPage);
            int end = endPage == -1 ? pageCount : Math.Min(endPage, pageCount);
            
            var text = string.Empty;
            for (int i = start; i <= end; i++)
            {
                var page = pdfDocument.GetPage(i);
                var strategy = new SimpleTextExtractionStrategy();
                text += PdfTextExtractor.GetTextFromPage(page, strategy);
                text += "\n\n";
            }
            
            return new ExtractionResult
            {
                Success = true,
                FullText = text.Trim(),
                PageRange = new PageRangeInfo
                {
                    TotalPages = pageCount,
                    StartPage = start,
                    EndPage = end
                }
            };
        }
        catch (Exception ex)
        {
            return new ExtractionResult
            {
                Success = false,
                ErrorMessage = ex.Message,
                PageRange = new PageRangeInfo
                {
                    TotalPages = 0,
                    StartPage = 0,
                    EndPage = 0
                }
            };
        }
    }
}

