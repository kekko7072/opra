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
            guard let page = pdf.page(at: pageIndex), let raw = page.string else { continue }
            let text = normalize(raw)
            guard !text.isEmpty else { continue }
            result.append(Passage(id: nextID, text: text, pageNumber: pageIndex + 1))
            nextID += 1
        }
        return result
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "-\n", with: "")     // join hyphenated line breaks
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
