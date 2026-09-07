import SwiftData
import SwiftUI

@main
struct TodoCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Todo Companion", systemImage: "bubble.left.and.text.bubble.right") {
            // No .keyboardShortcut on this one: the Carbon hotkey already owns
            // ⌥⌘Space globally, and a menu key equivalent would fire it a second
            // time once the panel activates the app.
            Button("Ask about my screen  (\(GlobalHotkey.defaultDisplayName))") {
                appDelegate.companion.summon()
            }

            LibraryMenuButton()

            Divider()

            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",", modifiers: .command)

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }

        Window("Saved Context", id: AppWindow.library) {
            LibraryView()
        }
        .modelContainer(ContextStore.shared)
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }
}

enum AppWindow {
    static let library = "library"
}

/// Needs its own view so it can reach `openWindow` from the menu's environment.
private struct LibraryMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Saved Context…") {
            openWindow(id: AppWindow.library)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
