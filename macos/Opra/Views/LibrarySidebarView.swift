//
//  LibrarySidebarView.swift
//  Opra
//
//  Left column: searchable library organized into user folders. Documents can be moved
//  between folders by drag-and-drop onto a folder, or via the row's "Move to Folder"
//  menu. Folders can be created, renamed, and deleted (deleting a folder keeps its PDFs,
//  moving them back to "Unfiled").
//

import SwiftUI
import TipKit

struct LibrarySidebarView: View {
    let documents: [LibraryDocument]
    let folders: [LibraryFolder]
    @Binding var selection: UUID?
    @Binding var searchText: String
    var activeDocID: UUID?
    var isReading: Bool
    var isImporting: Bool
    var onAdd: () -> Void
    var onDelete: (LibraryDocument) -> Void
    var onCreateFolder: (String) -> Void
    var onRenameFolder: (LibraryFolder, String) -> Void
    var onDeleteFolder: (LibraryFolder) -> Void
    var onMove: (UUID, LibraryFolder?) -> Void

    @State private var collapsed: Set<String> = []
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var folderToRename: LibraryFolder?
    @State private var renameName = ""

    private var sortedFolders: [LibraryFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var unfiled: [LibraryDocument] {
        documents.filter { $0.folder == nil }
    }
    private var searchResults: [LibraryDocument] {
        documents.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    header
                    if searchText.isEmpty {
                        ForEach(sortedFolders) { folder in
                            folderSection(folder)
                        }
                        groupSection(key: "unfiled", title: "Unfiled", icon: "tray",
                                     docs: unfiled, folder: nil)
                    } else {
                        ForEach(searchResults) { doc in documentRow(doc) }
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider()
            Button(action: onAdd) {
                Group {
                    if isImporting {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                            Text("Adding…")
                        }
                    } else {
                        Label("Add PDF", systemImage: "plus")
                    }
                }
                .fontWeight(.medium).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .padding(12)
            .popoverTip(AddPDFTip(), arrowEdge: .bottom)
        }
        .frame(minWidth: 230, idealWidth: 264, maxWidth: 340)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { onCreateFolder(name) }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { folderToRename != nil },
            set: { if !$0 { folderToRename = nil } }
        )) {
            TextField("Folder name", text: $renameName)
            Button("Rename") {
                if let folder = folderToRename {
                    let name = renameName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { onRenameFolder(folder, name) }
                }
                folderToRename = nil
            }
            Button("Cancel", role: .cancel) { folderToRename = nil }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.callout)
            TextField("Search library", text: $searchText).textFieldStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }

    private var header: some View {
        HStack {
            Text("LIBRARY").font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
            Spacer()
            Button { newFolderName = ""; showingNewFolder = true } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("New Folder")
            .popoverTip(FoldersTip(), arrowEdge: .top)
        }
        .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 4)
    }

    private func folderSection(_ folder: LibraryFolder) -> some View {
        groupSection(key: folder.id.uuidString, title: folder.name, icon: "folder",
                     docs: documents.filter { $0.folder?.id == folder.id }, folder: folder)
            .contextMenu {
                Button("Rename…") { renameName = folder.name; folderToRename = folder }
                Button("Delete Folder", role: .destructive) { onDeleteFolder(folder) }
            }
    }

    @ViewBuilder
    private func groupSection(key: String, title: String, icon: String,
                              docs: [LibraryDocument], folder: LibraryFolder?) -> some View {
        let isExpanded = !collapsed.contains(key)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2).foregroundStyle(.secondary).frame(width: 10)
                Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Text("\(docs.count)").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                if isExpanded { collapsed.insert(key) } else { collapsed.remove(key) }
            }
            .dropDestination(for: String.self) { items, _ in
                for raw in items { if let id = UUID(uuidString: raw) { onMove(id, folder) } }
                return true
            }

            if isExpanded {
                ForEach(docs) { doc in
                    documentRow(doc).padding(.leading, 12)
                }
            }
        }
    }

    private func documentRow(_ doc: LibraryDocument) -> some View {
        LibraryRow(doc: doc,
                   isSelected: doc.id == selection,
                   isActive: doc.id == activeDocID && isReading)
            .contentShape(Rectangle())
            .onTapGesture { selection = doc.id }
            .draggable(doc.id.uuidString)
            .contextMenu {
                Menu("Move to Folder") {
                    Button("Unfiled") { onMove(doc.id, nil) }
                    if !folders.isEmpty { Divider() }
                    ForEach(sortedFolders) { folder in
                        Button(folder.name) { onMove(doc.id, folder) }
                    }
                }
                Divider()
                Button("Remove from Library", role: .destructive) { onDelete(doc) }
            }
    }
}

private struct LibraryRow: View {
    let doc: LibraryDocument
    let isSelected: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(data: doc.thumbnailData).frame(width: 38, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.system(size: 13, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Text("\(doc.pageCount) pages").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isActive {
                Image(systemName: "waveform").font(.caption).foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(isSelected ? Color.primary.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ThumbnailView: View {
    let data: Data?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 4).fill(Color.white)
                .overlay(
                    Group {
                        if let data, let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "doc.text").foregroundStyle(.secondary)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.1)))
            Text("PDF")
                .font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 2))
                .padding(2)
        }
    }
}
