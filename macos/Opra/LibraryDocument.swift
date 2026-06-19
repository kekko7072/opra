//
//  LibraryDocument.swift
//  Opra
//
//  Persistent metadata for a PDF in the user's library. The original file is
//  referenced in place via an app-scoped security-scoped bookmark (the app does not
//  copy PDFs). Reading position and per-document removed passages persist here.
//

import Foundation
import SwiftData

@Model
final class LibraryDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var pageCount: Int
    /// App-scoped security-scoped bookmark to the original file.
    var bookmarkData: Data
    /// Cached page-1 thumbnail (PNG).
    @Attribute(.externalStorage) var thumbnailData: Data?
    var dateAdded: Date
    var lastOpened: Date?
    /// Resume point: index into the (non-deleted) reading queue.
    var lastPassageIndex: Int
    /// Passage IDs the user removed from the reading queue.
    var deletedPassageIDs: [Int]
    /// Folder this document belongs to, or nil for "Unfiled". Inverse of LibraryFolder.documents.
    var folder: LibraryFolder?

    init(
        id: UUID = UUID(),
        title: String,
        pageCount: Int,
        bookmarkData: Data,
        thumbnailData: Data? = nil,
        dateAdded: Date = Date(),
        lastOpened: Date? = nil,
        lastPassageIndex: Int = 0,
        deletedPassageIDs: [Int] = []
    ) {
        self.id = id
        self.title = title
        self.pageCount = pageCount
        self.bookmarkData = bookmarkData
        self.thumbnailData = thumbnailData
        self.dateAdded = dateAdded
        self.lastOpened = lastOpened
        self.lastPassageIndex = lastPassageIndex
        self.deletedPassageIDs = deletedPassageIDs
    }
}
