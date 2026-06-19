//
//  ReaderPaneView.swift
//  Opra
//
//  Center column: PDF page navigation header (Previous / Page X of N / Next, plus the
//  reading range and a Hide/Show Script toggle) over a PDFKit page view.
//

import SwiftUI
import PDFKit

struct ReaderPaneView: View {
    let pdfDocument: PDFDocument?
    @Binding var currentPage: Int
    let readingPageCount: Int
    @Binding var showScript: Bool
    let loadError: String?

    @State private var pdfView = PDFView()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { goPrevious() } label: { Label("Previous", systemImage: "chevron.left") }
                .disabled(!(pdfView.canGoToPreviousPage))
            Text("Page \(currentPage) of \(pdfDocument?.pageCount ?? 0)")
                .font(.callout).fontWeight(.medium)
            Button { goNext() } label: { Label("Next", systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle()) }
                .disabled(!(pdfView.canGoToNextPage))

            Spacer()

            if readingPageCount > 0 {
                Text("Reading 1–\(readingPageCount)").font(.callout).foregroundStyle(.secondary)
            }
            Button { showScript.toggle() } label: {
                Label(showScript ? "Hide Script" : "Show Script", systemImage: "list.bullet")
            }
            .buttonStyle(.bordered)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        if let pdfDocument {
            PDFViewRepresentable(pdfView: pdfView)
                .onAppear { setup(pdfDocument) }
                .onChange(of: pdfDocument) { _, newDoc in setup(newDoc) }
                .onChange(of: currentPage) { _, newPage in goToPage(newPage) }
                .padding(20)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 44)).foregroundStyle(.secondary)
                Text(loadError ?? "Select a PDF from your library to begin.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        }
    }

    private func setup(_ document: PDFDocument) {
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.interpolationQuality = .high
        goToPage(currentPage)
    }

    private func goToPage(_ page: Int) {
        guard let document = pdfView.document,
              let target = document.page(at: max(0, min(page - 1, document.pageCount - 1))) else { return }
        if pdfView.currentPage != target { pdfView.go(to: target) }
    }

    private func goPrevious() {
        pdfView.goToPreviousPage(nil)
        syncCurrentPage()
    }

    private func goNext() {
        pdfView.goToNextPage(nil)
        syncCurrentPage()
    }

    private func syncCurrentPage() {
        if let page = pdfView.currentPage, let document = pdfView.document {
            currentPage = document.index(for: page) + 1
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}
