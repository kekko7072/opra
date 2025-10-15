#ifdef __APPLE__

#include "PDFTextExtractor.h"
#include <CoreFoundation/CoreFoundation.h>
#include <PDFKit/PDFKit.h>
#include <Foundation/Foundation.h>

namespace Opra {

int PDFTextExtractor::Impl::getPageCountMacOS(const std::string& filePath) {
    @autoreleasepool {
        NSString* nsFilePath = [NSString stringWithUTF8String:filePath.c_str()];
        NSURL* fileURL = [NSURL fileURLWithPath:nsFilePath];
        
        PDFDocument* pdfDoc = [[PDFDocument alloc] initWithURL:fileURL];
        if (!pdfDoc) {
            return 0;
        }
        
        return (int)[pdfDoc pageCount];
    }
}

std::string PDFTextExtractor::Impl::extractTextFromPDFMacOS(const std::string& filePath, int startPage, int endPage) {
    @autoreleasepool {
        NSString* nsFilePath = [NSString stringWithUTF8String:filePath.c_str()];
        NSURL* fileURL = [NSURL fileURLWithPath:nsFilePath];
        
        PDFDocument* pdfDoc = [[PDFDocument alloc] initWithURL:fileURL];
        if (!pdfDoc) {
            return "";
        }
        
        NSMutableString* fullText = [NSMutableString string];
        
        // Convert to 0-based indexing
        int startIndex = std::max(0, startPage - 1);
        int endIndex = std::min((int)[pdfDoc pageCount], endPage);
        
        for (int i = startIndex; i < endIndex; i++) {
            PDFPage* page = [pdfDoc pageAtIndex:i];
            if (page) {
                NSString* pageText = [page string];
                if (pageText) {
                    [fullText appendFormat:@"--- Page %d ---\n", i + 1];
                    [fullText appendString:pageText];
                    [fullText appendString:@"\n\n"];
                }
            }
        }
        
        return std::string([fullText UTF8String]);
    }
}

} // namespace Opra

#endif // __APPLE__