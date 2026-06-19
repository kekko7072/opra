//
//  DocumentImporter.swift
//  Opra
//
//  Builds LibraryDocument records from user-selected PDFs (security-scoped bookmark +
//  page-1 thumbnail) and resolves bookmarks back to usable URLs.
//

import Foundation
import PDFKit
import AppKit

enum DocumentImporter {
    enum ImportError: LocalizedError {
        case notReadable
        var errorDescription: String? { "Could not read the selected PDF file." }
    }

    /// Create a library record for a user-selected URL. Caller owns inserting it into the model context.
    static func makeDocument(from url: URL) throws -> LibraryDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
            throw ImportError.notReadable
        }
        return LibraryDocument(
            title: url.deletingPathExtension().lastPathComponent,
            pageCount: pdf.pageCount,
            bookmarkData: bookmark,
            thumbnailData: thumbnail(for: pdf)
        )
    }

    /// Resolve a stored bookmark to a URL. `stale` indicates the bookmark should be refreshed.
    static func resolveURL(from bookmark: Data) -> (url: URL, isStale: Bool)? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        return (url, stale)
    }

    /// Render a page-1 thumbnail as PNG data.
    static func thumbnail(for pdf: PDFDocument, maxDimension: CGFloat = 320) -> Data? {
        guard let page = pdf.page(at: 0) else { return nil }
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = min(maxDimension / box.width, maxDimension / box.height, 2.0)
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png
    }
}
