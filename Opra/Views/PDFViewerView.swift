//
//  PDFViewerView.swift
//  Opra
//
//  Created by Francesco Vezzani on 12/10/25.
//

import SwiftUI
import PDFKit
import AVFoundation

struct PDFViewerView: View {
    let pdfDocument: PDFDocument
    @Binding var currentPage: Int
    @ObservedObject var ttsProviderManager: TTSProviderManager
    @State private var pdfView = PDFView()
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation controls
            HStack {
                Button("Previous") {
                    pdfView.goToPreviousPage(nil)
                    updateCurrentPage()
                }
                .buttonStyle(.bordered)
                .disabled(!pdfView.canGoToPreviousPage)
                
                Text("Page \(currentPage) of \(pdfDocument.pageCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 120)
                
                Button("Next") {
                    pdfView.goToNextPage(nil)
                    updateCurrentPage()
                }
                .buttonStyle(.bordered)
                .disabled(!pdfView.canGoToNextPage)
                
                Spacer()
                
                // Page jump
                HStack {
                    Text("Go to:")
                    TextField("Page", value: $currentPage, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onSubmit {
                            jumpToPage()
                        }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // PDF content with vertical scrolling
            ZStack {
                PDFViewRepresentable(pdfView: pdfView)
                    .onAppear {
                        setupPDFView()
                    }
            }
        }
    }
    
    private func setupPDFView() {
        pdfView.document = pdfDocument
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.interpolationQuality = .high
        
    }
    
    
    private func updateCurrentPage() {
        if let page = pdfView.currentPage {
            let pageIndex = pdfDocument.index(for: page)
            currentPage = pageIndex + 1
        }
    }
    
    private func jumpToPage() {
        let targetPage = max(1, min(currentPage, pdfDocument.pageCount))
        if let page = pdfDocument.page(at: targetPage - 1) {
            pdfView.go(to: page)
            currentPage = targetPage
        }
    }
}
