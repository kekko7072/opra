//
//  OpraTips.swift
//  Opra
//
//  TipKit coaching tips and configuration. Tips are configured only after onboarding
//  completes (so they don't appear behind the setup guide), and staggered with rules
//  so the user isn't shown everything at once.
//

import SwiftUI
import TipKit

enum OpraTips {
    private static var configured = false

    /// Idempotent — safe to call on launch and again when onboarding finishes.
    static func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }
}

/// Shown on the "Add PDF" button — the first thing a new user needs.
struct AddPDFTip: Tip {
    var title: Text { Text("Build your library") }
    var message: Text? { Text("Import PDFs here, then drag them into folders to stay organized.") }
    var image: Image? { Image(systemName: "plus.rectangle.on.folder") }
}

/// Shown on the voice chip once a document has been opened.
struct VoiceTip: Tip {
    @Parameter static var documentOpened: Bool = false

    var title: Text { Text("Choose your voice") }
    var message: Text? { Text("Switch between on-device Kokoro, system, and OpenAI voices — and pick a specific voice.") }
    var image: Image? { Image(systemName: "waveform") }
    var rules: [Rule] { [#Rule(Self.$documentOpened) { $0 }] }
}

/// Shown near the library once the user has at least one PDF.
struct FoldersTip: Tip {
    @Parameter static var hasDocuments: Bool = false

    var title: Text { Text("Stay organized") }
    var message: Text? { Text("Create folders and drag PDFs into them, or use a document's “Move to Folder” menu.") }
    var image: Image? { Image(systemName: "folder") }
    var rules: [Rule] { [#Rule(Self.$hasDocuments) { $0 }] }
}
