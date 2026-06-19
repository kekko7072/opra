//
//  UpdaterController.swift
//  Opra
//
//  Wraps Sparkle's standard updater for direct (non-App-Store) distribution. The feed
//  URL and EdDSA public key live in Info.plist (SUFeedURL / SUPublicEDKey); releases are
//  signed with Sparkle's sign_update and published to the appcast.
//

import Foundation
import Sparkle

@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Trigger a user-initiated update check (shows Sparkle's standard UI).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
