//
//  Passage.swift
//  Opra
//
//  A unit of the reading script — a sentence (or merged short fragment) tagged with
//  its source page. Passages are both the display unit in the Reading Script panel
//  and the synthesis unit fed to the TTS engine.
//

import Foundation

struct Passage: Identifiable, Equatable {
    /// Stable index into the document's full (pre-deletion) passage list.
    let id: Int
    let text: String
    /// 1-based source page.
    let pageNumber: Int
}
