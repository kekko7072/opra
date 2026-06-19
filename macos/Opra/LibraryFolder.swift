//
//  LibraryFolder.swift
//  Opra
//
//  A user-created folder for organizing the PDF library. Documents reference their
//  folder via LibraryDocument.folder; deleting a folder nullifies that link (the
//  documents move back to "Unfiled" rather than being deleted).
//

import Foundation
import SwiftData

@Model
final class LibraryFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var dateAdded: Date

    @Relationship(deleteRule: .nullify, inverse: \LibraryDocument.folder)
    var documents: [LibraryDocument] = []

    init(id: UUID = UUID(), name: String, dateAdded: Date = Date()) {
        self.id = id
        self.name = name
        self.dateAdded = dateAdded
    }
}
