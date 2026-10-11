import Foundation
#if !APP_STORE
import Sparkle
#endif

/// Sparkle updater for the Developer ID / direct-download channel.
///
/// Mac App Store builds compile this out (`APP_STORE`) — Apple’s updater
/// replaces Sparkle there (see docs/APP_STORE.md).
@MainActor
enum AppUpdate {
#if APP_STORE
    static var isAvailable: Bool { false }
    static func start() {}
    static func checkForUpdates() {}
#else
    private static var controller: SPUStandardUpdaterController?

    static var isAvailable: Bool {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let pub = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return feed.map { !$0.isEmpty } == true && pub.map { !$0.isEmpty } == true
    }

    /// Starts background update checks when a feed URL and public key exist.
    static func start() {
        guard controller == nil, isAvailable else { return }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// User-initiated check from the menu bar.
    static func checkForUpdates() {
        if controller == nil { start() }
        controller?.checkForUpdates(nil)
    }
#endif
}
