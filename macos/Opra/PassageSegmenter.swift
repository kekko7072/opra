//
//  PassageSegmenter.swift
//  Opra
//
//  Turns a PDF into an ordered, page-tagged list of reading passages. Each page becomes
//  a single passage holding the whole page's normalized (de-hyphenated,
//  whitespace-collapsed) text, so reading chunks are as large as the page allows.
//  Providers with a per-request limit (OpenAI, Kokoro) re-split a passage into
//  model-sized speech chunks internally; passage highlighting still tracks whole pages.
//

import Foundation
import PDFKit

enum PassageSegmenter {
    static func passages(for pdf: PDFDocument) -> [Passage] {
        var result: [Passage] = []
        var nextID = 0
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            let reconstructed = PDFTextNormalizer.text(from: page)
            let text = PDFTextNormalizer.excludingPageFurniture(from: page, text: reconstructed)
            guard !text.isEmpty else { continue }

            // Keep headings and body paragraphs distinct. Preserve page mapping
            // for navigation while allowing screen readers/TTS to pause naturally.
            let blocks = text.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for block in blocks {
                result.append(Passage(id: nextID, text: block, pageNumber: pageIndex + 1))
                nextID += 1
            }
        }
        return result
    }

}
