import AppKit
import SwiftData
import SwiftUI

@MainActor
final class CompanionPanelController {
    /// Only the starting height. The panel resizes to whatever the content
    /// actually needs once SwiftUI has laid it out.
    private static let initialSize = NSSize(width: DS.Size.panelWidth, height: 180)

    let viewModel: CompanionViewModel
    private var panel: CompanionPanel?
    private weak var previousApp: NSRunningApplication?

    private let indicator = CaptureIndicator()
    private var outsideClickMonitor: Any?

    init(modelContext: ModelContext) {
        self.viewModel = CompanionViewModel(modelContext: modelContext)
        viewModel.onCaptureBegan = { [weak self] in self?.indicator.show(.capturing) }
        viewModel.onCaptureEnded = { [weak self] in self?.indicator.hide() }
        viewModel.onListeningBegan = { [weak self] in
            self?.indicator.show(.listening, level: { [weak self] in self?.viewModel.currentInputLevel ?? 0 })
        }
        viewModel.onListeningEnded = { [weak self] in self?.indicator.hide() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : summon()
    }

    /// Reads the frontmost app before activating ourselves, otherwise the
    /// captured context would just say "TodoCompanion".
    func summon() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }

        let panel = existingPanel()
        panel.setFrameTopLeftPoint(topLeftNearCursor(for: panel.frame.size))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        watchForOutsideClick()

        viewModel.captureScreen(frontmostApp: frontmost)
    }

    /// Dismisses when the user clicks away, which is what every other floating
    /// panel on the system does. Only mouse events are observed: a global
    /// *keyboard* monitor would demand Accessibility permission, and avoiding
    /// that is why the hotkey uses Carbon in the first place.
    private func watchForOutsideClick() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    /// Steps the panel aside for region selection without tearing down its
    /// state, and suspends the outside-click monitor that would otherwise treat
    /// the drag as a dismissal.
    private func setPanelHidden(_ hidden: Bool) {
        guard let panel else { return }
        if hidden {
            stopWatchingForOutsideClick()
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            watchForOutsideClick()
        }
    }

    private func stopWatchingForOutsideClick() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// Hands focus back to whatever the user was working in, so the companion
    /// does not leave them staring at an empty desktop.
    func hide() {
        stopWatchingForOutsideClick()
        panel?.orderOut(nil)
        viewModel.reset()
        previousApp?.activate()
        previousApp = nil
    }

    private func existingPanel() -> CompanionPanel {
        if let panel { return panel }

        let panel = CompanionPanel(contentRect: NSRect(origin: .zero, size: Self.initialSize))
        panel.onDismiss = { [weak self] in self?.hide() }

        let hosting = NSHostingController(
            rootView: CompanionView(
                viewModel: viewModel,
                onClose: { [weak self] in self?.hide() },
                onRetry: { [weak self] in
                    self?.viewModel.retryCapture(frontmostApp: self?.previousApp)
                },
                onSelectRegion: { [weak self] in
                    self?.viewModel.selectRegion { hidden in
                        // Clicking into the selection overlay is a click outside
                        // the panel, so the dismiss monitor has to stand down.
                        self?.setPanelHidden(hidden)
                    }
                },
                onClearRegion: { [weak self] in
                    self?.viewModel.clearRegion(frontmostApp: self?.previousApp)
                }
            )
        )
        // Lets the answer drive the window height rather than a fixed guess.
        hosting.sizingOptions = .preferredContentSize
        panel.contentViewController = hosting

        self.panel = panel
        return panel
    }

    /// Returns the top-left corner, because that is the edge the panel keeps
    /// fixed as it grows downward with the answer.
    private func topLeftNearCursor(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let gap: CGFloat = 18
        var x = mouse.x + gap
        if x + size.width > bounds.maxX { x = mouse.x - size.width - gap }
        x = min(max(x, bounds.minX + 8), bounds.maxX - size.width - 8)

        // Hang below the cursor, but flip above it near the bottom of the screen
        // so a tall answer still has somewhere to grow.
        var top = mouse.y - gap
        if top - size.height < bounds.minY { top = mouse.y + gap + size.height }
        top = min(max(top, bounds.minY + size.height + 8), bounds.maxY - 8)

        return NSPoint(x: x, y: top)
    }
}
