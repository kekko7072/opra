//
//  PassageSegmenter.swift
//  Opra
//
//  Turns a PDF into an ordered, page-tagged list of reading passages. Text is
//  normalized (de-hyphenated, whitespace-collapsed) then split into sentences with
//  Foundation's locale-aware sentence enumerator; very short fragments (headings,
//  stray tokens) are merged forward so the reader gets sensible spans.
//

import Foundation
import PDFKit

enum PassageSegmenter {
    static func passages(for pdf: PDFDocument, minLength: Int = 40) -> [Passage] {
        var result: [Passage] = []
        var nextID = 0
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex), let raw = page.string else { continue }
            let text = normalize(raw)
            guard !text.isEmpty else { continue }
            for sentence in mergeShort(splitSentences(text), minLength: minLength) {
                result.append(Passage(id: nextID, text: sentence, pageNumber: pageIndex + 1))
                nextID += 1
            }
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

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                                 options: [.bySentences, .localized]) { sub, _, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        return sentences.isEmpty ? [text] : sentences
    }

    private static func mergeShort(_ sentences: [String], minLength: Int) -> [String] {
        var merged: [String] = []
        var buffer = ""
        for s in sentences {
            buffer = buffer.isEmpty ? s : buffer + " " + s
            if buffer.count >= minLength {
                merged.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty {
            if merged.isEmpty { merged.append(buffer) } else { merged[merged.count - 1] += " " + buffer }
        }
        return merged
    }
}
