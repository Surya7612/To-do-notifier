import AppKit
import SwiftData
import SwiftUI

@MainActor
final class CompanionPanelController {
    static let size = NSSize(width: 420, height: 400)

    let viewModel: CompanionViewModel
    private var panel: CompanionPanel?
    private weak var previousApp: NSRunningApplication?

    private let indicator = CaptureIndicator()

    init(modelContext: ModelContext) {
        self.viewModel = CompanionViewModel(modelContext: modelContext)
        viewModel.onCaptureBegan = { [weak self] in self?.indicator.show() }
        viewModel.onCaptureEnded = { [weak self] in self?.indicator.hide() }
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
        panel.setFrame(NSRect(origin: originNearCursor(), size: Self.size), display: false)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        viewModel.captureScreen(frontmostApp: frontmost)
    }

    /// Hands focus back to whatever the user was working in, so the companion
    /// does not leave them staring at an empty desktop.
    func hide() {
        panel?.orderOut(nil)
        viewModel.reset()
        previousApp?.activate()
        previousApp = nil
    }

    private func existingPanel() -> CompanionPanel {
        if let panel { return panel }

        let panel = CompanionPanel(contentRect: NSRect(origin: .zero, size: Self.size))
        panel.onDismiss = { [weak self] in self?.hide() }
        panel.contentView = NSHostingView(
            rootView: CompanionView(
                viewModel: viewModel,
                onClose: { [weak self] in self?.hide() },
                onRetry: { [weak self] in
                    self?.viewModel.retryCapture(frontmostApp: self?.previousApp)
                }
            )
        )
        self.panel = panel
        return panel
    }

    private func originNearCursor() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let gap: CGFloat = 18
        var x = mouse.x + gap
        var y = mouse.y - Self.size.height - gap

        if x + Self.size.width > bounds.maxX { x = mouse.x - Self.size.width - gap }
        if y < bounds.minY { y = mouse.y + gap }

        x = min(max(x, bounds.minX + 8), bounds.maxX - Self.size.width - 8)
        y = min(max(y, bounds.minY + 8), bounds.maxY - Self.size.height - 8)
        return NSPoint(x: x, y: y)
    }
}
