//
//  ReaderPaneView.swift
//  Opra
//
//  Center column: PDF page navigation header (Previous / Page X of N / Next, plus the
//  reading range and a Hide/Show Script toggle) over a PDFKit page view.
//

import SwiftUI
import PDFKit
import AppKit

struct ReaderPaneView: View {
    let pdfDocument: PDFDocument?
    @Binding var currentPage: Int
    let readingPageCount: Int
    @Binding var showScript: Bool
    let loadError: String?
    let isPageHidden: Bool
    var onToggleHidePage: () -> Void

    @State private var pdfView = PDFView()
    @State private var pageChangeObserver: NSObjectProtocol?
    @State private var scrollObserver: NSObjectProtocol?
    @State private var pageTrackingTimer: Timer?
    @State private var lastCommandedPage = 1
    @State private var isUpdatingPageFromScroll = false

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

            if pdfDocument != nil {
                Button(action: onToggleHidePage) {
                    Label(isPageHidden ? "Page Skipped" : "Skip Page",
                          systemImage: isPageHidden ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                .tint(isPageHidden ? .orange : nil)
                .help(isPageHidden ? "This page is skipped — click to read it again"
                                   : "Skip this page when reading")
            }
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
                .onChange(of: currentPage) { _, newPage in
                    guard !isUpdatingPageFromScroll, newPage != lastCommandedPage else { return }
                    lastCommandedPage = newPage
                    goToPage(newPage)
                }
                .onDisappear { stopPageTracking() }
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
        // Defer off the current SwiftUI layout pass — mutating the PDFView (and the
        // implicit go(to:) layout) while the view is being laid out triggers an
        // AppKit layout-recursion warning.
        DispatchQueue.main.async {
            pdfView.document = document
            pdfView.autoScales = true
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
            pdfView.interpolationQuality = .high
            removePageObservers()
            pageChangeObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { _ in
                syncCurrentPage()
            }
            installScrollObserverWhenReady(attempt: 0)
            pageTrackingTimer?.invalidate()
            pageTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                syncMostVisiblePage()
            }
            goToPage(currentPage)
        }
    }

    private func installScrollObserverWhenReady(attempt: Int) {
        guard attempt < 20 else { return }
        DispatchQueue.main.async {
            guard let clipView = pdfView.documentView?.enclosingScrollView?.contentView else {
                installScrollObserverWhenReady(attempt: attempt + 1)
                return
            }
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            clipView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { _ in syncMostVisiblePage() }
        }
    }

    private func removePageObservers() {
        if let pageChangeObserver { NotificationCenter.default.removeObserver(pageChangeObserver) }
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        pageChangeObserver = nil
        scrollObserver = nil
    }

    private func stopPageTracking() {
        pageTrackingTimer?.invalidate()
        pageTrackingTimer = nil
        removePageObservers()
    }

    private func goToPage(_ page: Int) {
        DispatchQueue.main.async {
            guard let document = pdfView.document,
                  let target = document.page(at: max(0, min(page - 1, document.pageCount - 1))) else { return }
            if pdfView.currentPage != target { pdfView.go(to: target) }
            syncMostVisiblePage()
        }
    }

    private func goPrevious() {
        let target = max(1, currentPage - 1)
        lastCommandedPage = target
        currentPage = target
        goToPage(target)
    }

    private func goNext() {
        let target = min(pdfDocument?.pageCount ?? currentPage, currentPage + 1)
        lastCommandedPage = target
        currentPage = target
        goToPage(target)
    }

    private func syncCurrentPage() {
        if let page = pdfView.currentPage, let document = pdfView.document {
            let newPage = document.index(for: page) + 1
            if currentPage != newPage { currentPage = newPage }
        }
    }

    /// In continuous vertical mode PDFView's currentPage notification can lag
    /// behind manual scrolling. Pick the page with the largest visible area.
    private func syncMostVisiblePage() {
        guard let document = pdfView.document else { return }
        let visibleRect = pdfView.bounds
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for page in pdfView.visiblePages {
            let pageRect = pdfView.convert(page.bounds(for: .cropBox), from: page)
            let intersection = pageRect.intersection(visibleRect)
            let area = intersection.isNull ? 0 : max(0, intersection.width) * max(0, intersection.height)
            if area > bestArea {
                bestArea = area
                bestIndex = document.index(for: page)
            }
        }
        if let bestIndex, currentPage != bestIndex + 1 {
            isUpdatingPageFromScroll = true
            currentPage = bestIndex + 1
            lastCommandedPage = bestIndex + 1
            DispatchQueue.main.async {
                isUpdatingPageFromScroll = false
            }
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}
