//
//  DocumentImporter.swift
//  Opra
//
//  Imports user-selected PDFs by copying them into the app's Library container, so the
//  sandbox can always read them later without security-scoped bookmarks (which proved
//  unreliable). Also renders the page-1 thumbnail.
//

import Foundation
import PDFKit
import AppKit

enum DocumentImporter {
    enum ImportError: LocalizedError {
        case notReadable
        var errorDescription: String? { "Could not read the selected PDF file." }
    }

    /// Plain (Sendable) result of importing a file — safe to produce off the main
    /// thread; the SwiftData LibraryDocument is created from it on the main actor.
    struct ImportedPDF: Sendable {
        let title: String
        let pageCount: Int
        let storedFileName: String
        let thumbnailData: Data?
    }

    /// Directory inside the app container where imported PDFs are stored.
    static var libraryDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Opra/Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(for doc: LibraryDocument) -> URL {
        libraryDirectory.appendingPathComponent(doc.storedFileName)
    }

    /// Copy a user-selected PDF into the library container and read its metadata.
    /// Safe to call off the main thread (does file I/O + thumbnail rendering).
    static func importFile(from url: URL) throws -> ImportedPDF {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
            throw ImportError.notReadable
        }

        let fileName = "\(UUID().uuidString).pdf"
        let dest = libraryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: url, to: dest)

        return ImportedPDF(
            title: url.deletingPathExtension().lastPathComponent,
            pageCount: pdf.pageCount,
            storedFileName: fileName,
            thumbnailData: thumbnail(for: pdf)
        )
    }

    /// Remove the copied PDF when a document is deleted from the library.
    static func deleteStoredFile(for doc: LibraryDocument) {
        try? FileManager.default.removeItem(at: fileURL(for: doc))
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
