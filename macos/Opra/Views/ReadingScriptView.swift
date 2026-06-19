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
    let activeIndex: Int
    let isReading: Bool
    var onPlay: (Passage) -> Void
    var onDelete: (Passage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reading Script").font(.headline)
                Spacer()
                Text("\(passages.count) passages")
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

                        ForEach(Array(passages.enumerated()), id: \.element.id) { index, passage in
                            PassageRow(
                                passage: passage,
                                isActive: isReading && index == activeIndex,
                                onPlay: { onPlay(passage) },
                                onDelete: { onDelete(passage) }
                            )
                            .id(index)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .onChange(of: activeIndex) { _, newValue in
                    guard isReading else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
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
