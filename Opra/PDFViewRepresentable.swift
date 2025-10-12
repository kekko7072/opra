//
//  PDFViewRepresentable.swift
//  Opra
//
//  Created by Francesco Vezzani on 12/10/25.
//

import SwiftUI
import PDFKit

struct PDFViewRepresentable: NSViewRepresentable {
    let pdfView: PDFView
    
    func makeNSView(context: Context) -> PDFView {
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        // No updates needed
    }
}
