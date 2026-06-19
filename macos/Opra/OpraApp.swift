//
//  OpraApp.swift
//  Opra
//
//  Created by Francesco Vezzani on 12/10/25.
//

import SwiftUI
import SwiftData

@main
struct OpraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [LibraryDocument.self, LibraryFolder.self])
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdaterController.shared.checkForUpdates() }
            }
        }
    }
}
