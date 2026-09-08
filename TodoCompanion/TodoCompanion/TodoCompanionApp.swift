import SwiftData
import SwiftUI

@main
struct TodoCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
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
        } label: {
            MenuBarLabel()
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

/// Lets code outside SwiftUI open the library.
///
/// `openWindow` only exists in a view's environment, and a fired reminder is
/// handled in the app delegate. Rather than reach for a URL scheme for one
/// internal navigation, the menu bar label — the one view that is always
/// instantiated, since the status item is always on screen — hands the action
/// over at launch.
@MainActor
enum LibraryWindow {
    static var opener: (() -> Void)?

    static func open() { opener?() }
}

private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "bubble.left.and.text.bubble.right")
            .accessibilityLabel("Todo Companion")
            .onAppear {
                LibraryWindow.opener = { openWindow(id: AppWindow.library) }
            }
    }
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
