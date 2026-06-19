//
//  ReadingScriptView.swift
//  Opra
//
//  Right column: the reading script as a list of passages. Each passage can be played
//  from (speaker) or removed from the queue (trash). The active passage is highlighted
//  and auto-scrolled into view.
//

import SwiftUI

struct ReadingScriptView: View {
    let documentTitle: String
    let passages: [Passage]
    let removedPassages: [Passage]
    let activeIndex: Int
    let isReading: Bool
    let isLoading: Bool
    var onPlay: (Passage) -> Void
    var onDelete: (Passage) -> Void
    var onRestore: (Passage) -> Void
    var onRestoreAll: () -> Void

    @State private var showingRemoved = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Reading Script").font(.headline)
                Spacer()
                if !removedPassages.isEmpty {
                    Button { showingRemoved.toggle() } label: {
                        Label("\(removedPassages.count) removed", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(showingRemoved ? Color.accentColor : .secondary)
                    .help("Show passages you removed so you can restore them")
                }
                Text(isLoading ? "Preparing…" : "\(passages.count) passages")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        Text(documentTitle)
                            .font(.headline)
                            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

                        if passages.isEmpty && isLoading {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Preparing reading script…").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                        }

                        ForEach(Array(passages.enumerated()), id: \.element.id) { index, passage in
                            PassageRow(
                                passage: passage,
                                isActive: isReading && index == activeIndex,
                                onPlay: { onPlay(passage) },
                                onDelete: { onDelete(passage) }
                            )
                            // Identify rows by the stable passage id (NOT the array index),
                            // so deleting a passage removes that exact row from the list.
                            .id(passage.id)
                        }

                        if showingRemoved && !removedPassages.isEmpty {
                            Divider().padding(.top, 10).padding(.bottom, 2)
                            HStack {
                                Text("Removed").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                Button("Restore all", action: onRestoreAll)
                                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 2)

                            ForEach(removedPassages) { passage in
                                RemovedPassageRow(passage: passage, onRestore: { onRestore(passage) })
                                    .id(passage.id)
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .onChange(of: activeIndex) { _, newValue in
                    guard isReading, passages.indices.contains(newValue) else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(passages[newValue].id, anchor: .center)
                    }
                }
            }
        }
        .onChange(of: removedPassages.isEmpty) { _, isEmpty in
            if isEmpty { showingRemoved = false }
        }
        .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PassageRow: View {
    let passage: Passage
    let isActive: Bool
    var onPlay: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isActive {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3)
            } else {
                Color.clear.frame(width: 3)
            }

            Text(passage.text)
                .font(.system(size: 14))
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button(action: onPlay) {
                    Image(systemName: "speaker.wave.2")
                }
                .help("Read from here")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("Remove from reading")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering || isActive ? 1 : 0.35)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isActive ? Color.accentColor.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// A passage the user removed from the queue, shown dimmed with a restore button.
private struct RemovedPassageRow: View {
    let passage: Passage
    var onRestore: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear.frame(width: 3)

            Text(passage.text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .strikethrough(true, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0.5)
            .help("Restore to reading")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
