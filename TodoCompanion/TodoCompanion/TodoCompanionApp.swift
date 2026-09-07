import SwiftUI

@main
struct TodoCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Todo Companion", systemImage: "bubble.left.and.text.bubble.right") {
            // No .keyboardShortcut here: the Carbon hotkey already owns ⌥⌘Space
            // globally, and a menu key equivalent would fire it a second time
            // once the panel activates the app.
            Button("Ask about my screen  (\(GlobalHotkey.defaultDisplayName))") {
                appDelegate.companion.summon()
            }

            Divider()

            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",", modifiers: .command)

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            SettingsView()
        }
    }
}
