import SwiftUI
import SwiftData

@main
struct OpraApp: App {
    var body: some Scene {
        WindowGroup { MobileLibraryView() }
            .modelContainer(for: [LibraryDocument.self, LibraryFolder.self])
    }
}
