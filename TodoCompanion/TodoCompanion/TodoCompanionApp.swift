import SwiftData
import SwiftUI

@main
struct TodoCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Todo Companion", systemImage: "bubble.left.and.text.bubble.right") {
            // No .keyboardShortcut on this one: the Carbon hotkey already owns
            // the combo globally, and a menu key equivalent would fire it a
            // second time once the panel activates the app.
            SummonMenuButton { appDelegate.companion.summon() }

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

/// Its own view so the label tracks the shortcut chosen in Settings.
private struct SummonMenuButton: View {
    @AppStorage(AppSettings.Key.hotkeyID) private var hotkeyID = HotkeyChoice.fallback.id
    let action: () -> Void

    var body: some View {
        Button("Ask about my screen  (\(HotkeyChoice.named(hotkeyID).displayName))", action: action)
    }
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
