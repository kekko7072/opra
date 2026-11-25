//
//  PDFTextNormalizer.swift
//  Opra
//
//  Repairs the two most common defects in PDFKit's logical text stream:
//  missing word spaces and line-break hyphenation. PDF files position glyphs
//  rather than storing paragraphs, so the visual gap is often the only record
//  of a space.
//

import Foundation
import PDFKit

enum PDFTextNormalizer {
    static func text(from page: PDFPage) -> String {
        guard let raw = page.string, !raw.isEmpty else { return "" }
        let utf16Count = (raw as NSString).length

        // PDFKit character indexes and NSString indexes are both UTF-16 based.
        // Some malformed PDFs still expose inconsistent counts; in that case
        // use the safe whitespace cleanup rather than associating wrong boxes.
        guard page.numberOfCharacters == utf16Count else {
            return normalize(raw)
        }

        let bounds = (0..<utf16Count).map { page.characterBounds(at: $0) }
        guard bounds.contains(where: { !$0.isEmpty }) else { return normalize(raw) }
        return normalize(reconstructReadingOrder(raw: raw, bounds: bounds))
    }

    /// Text in the top/bottom margins is page furniture. Use geometry to remove
    /// only short folio/header/footer lines well outside the main text block.
    static func excludingPageFurniture(from page: PDFPage, text: String) -> String {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.height > 0 else { return text }
        let lineItems = visualLines(raw: page.string ?? "", bounds: (0..<((page.string as NSString?)?.length ?? 0)).map { page.characterBounds(at: $0) })
        guard !lineItems.isEmpty else { return text }
        let body = lineItems.filter { line, rect in
            let location = (rect.midY - pageBounds.minY) / pageBounds.height
            let isMargin = location > 0.91 || location < 0.08
            let isFolio = isPageFolio(line)
            let isShortMarginLine = line.count < 48 && isMargin
            return !(isMargin && (isFolio || isShortMarginLine))
        }
        return body.map(\.0).joined(separator: "\n")
    }

    /// Rebuild text line by line using glyph positions. A gap threshold adapts
    /// to the current font size, and line transitions are emitted as newlines
    /// so headings and paragraphs keep natural reading pauses.
    private static func reconstructReadingOrder(raw: String, bounds: [CGRect]) -> String {
        let source = raw as NSString
        guard source.length == bounds.count else { return raw }
        let visual = visualLines(raw: raw, bounds: bounds)
        guard !visual.isEmpty else { return raw }

        var previousRect: CGRect?
        var output: [String] = []
        for (line, rect) in visual {
            guard !line.isEmpty else { continue }
            if let previousRect {
                let verticalGap = previousRect.minY - rect.maxY
                let lineHeight = max(previousRect.height, rect.height)
                output.append(verticalGap > lineHeight * 0.7 ? "\n\n" : "\n")
            }
            output.append(line)
            previousRect = rect
        }
        return output.joined()
    }

    private static func visualLines(raw: String, bounds: [CGRect]) -> [(String, CGRect)] {
        let source = raw as NSString
        guard source.length == bounds.count else { return [] }
        var lines: [(y: CGFloat, entries: [(Int, CGRect)])] = []

        for index in 0..<source.length {
            let character = source.substring(with: NSRange(location: index, length: 1))
            let rect = bounds[index]
            if character.rangeOfCharacter(from: .newlines) != nil {
                continue
            }
            guard !rect.isEmpty else { continue }
            if let nearest = lines.indices.min(by: { abs(lines[$0].y - rect.midY) < abs(lines[$1].y - rect.midY) }),
               abs(lines[nearest].y - rect.midY) < max(2, rect.height * 0.45) {
                lines[nearest].entries.append((index, rect))
            } else {
                lines.append((rect.midY, [(index, rect)]))
            }
        }

        return lines.sorted { $0.y > $1.y }.compactMap { line in
            let sorted = line.entries.sorted { $0.1.minX < $1.1.minX }
            guard let union = sorted.map(\.1).dropFirst().reduce(sorted.first?.1, { $0?.union($1) }),
                  let first = sorted.first else { return nil }
            var text = ""
            var previous: (Int, CGRect)?
            for (index, rect) in sorted {
                let character = source.substring(with: NSRange(location: index, length: 1))
                if let previous,
                   index > previous.0,
                   needsSpace(between: source.substring(with: NSRange(location: previous.0, length: 1)), and: character,
                              previousBounds: previous.1, currentBounds: rect) {
                    text.append(" ")
                }
                text.append(character)
                previous = (index, rect)
            }
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), union.union(first.1))
        }
    }

    static func normalize(_ text: String) -> String {
        let dehyphenated = text
            // Remove line-wrap hyphens, but never sentence punctuation such as
            // en/em dashes (which are meaningful to speech cadence).
            .replacingOccurrences(of: "[-\\x{00AD}\\x{2010}][ \\t]*\\n[ \\t]*(?=\\p{L})", with: "", options: .regularExpression)
        let normalizedLines = dehyphenated.components(separatedBy: .newlines).map {
            $0.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        var output = ""
        var previousWasBlank = false
        var previousLine: String?
        for line in normalizedLines {
            if line.isEmpty {
                if !output.isEmpty { previousWasBlank = true }
                continue
            }

            if !output.isEmpty {
                if previousWasBlank {
                    output += "\n\n"
                } else if let previousLine,
                          previousLine.hasSuffix("—") || previousLine.hasSuffix("–") {
                    output += "\n"
                } else {
                    output += " "
                }
            }
            output += line
            previousLine = line
            previousWasBlank = false
        }
        return output
    }

    /// Inserts a space where consecutive non-whitespace characters are on the
    /// same visual line but separated by a word-sized horizontal gap.
    static func repairMissingSpaces(in text: String, bounds: [CGRect]) -> String {
        let source = text as NSString
        guard source.length == bounds.count, source.length > 1 else { return text }

        var result = ""
        var previousIndex: Int?

        for index in 0..<source.length {
            let scalar = source.substring(with: NSRange(location: index, length: 1))
            if let previousIndex,
               needsSpace(
                   between: source.substring(with: NSRange(location: previousIndex, length: 1)),
                   and: scalar,
                   previousBounds: bounds[previousIndex],
                   currentBounds: bounds[index]
               ) {
                result.append(" ")
            }
            result.append(scalar)
            previousIndex = index
        }
        return result
    }


    static func isPageFolio(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        return value.range(of: "^(?:[0-9]{1,4}|[ivxlcdm]{1,10})$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func needsSpace(
        between previous: String,
        and current: String,
        previousBounds: CGRect,
        currentBounds: CGRect
    ) -> Bool {
        guard previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              current.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !previousBounds.isEmpty, !currentBounds.isEmpty else { return false }

        let verticalOverlap = min(previousBounds.maxY, currentBounds.maxY)
            - max(previousBounds.minY, currentBounds.minY)
        let sameLine = verticalOverlap >= min(previousBounds.height, currentBounds.height) * 0.5
        guard sameLine else { return false }

        let gap = currentBounds.minX - previousBounds.maxX
        let fontScale = min(previousBounds.height, currentBounds.height)
        // Typical word spaces are roughly 20–30% of the font size. A 14%
        // threshold stays above normal kerning while recovering narrow spaces.
        return gap > max(0.75, fontScale * 0.14)
    }
}
