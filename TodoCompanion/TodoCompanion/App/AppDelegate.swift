import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var companion = CompanionPanelController(modelContext: ContextStore.shared.mainContext)

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        NSApp.setActivationPolicy(.accessory)

        GlobalHotkey.shared.activate(AppSettings.hotkey) { [weak self] in
            self?.companion.toggle()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkey.shared.unregister()
    }
}
