import AppKit

/// Drag-to-select a rectangle of the screen.
///
/// This crops the screenshot already taken when the panel was summoned rather
/// than capturing again: the pixels are in memory, so selecting a region costs
/// nothing, cannot flicker, and cannot race a screen that changed in between.
///
/// Note that this is the user pointing at something, not the model pointing at
/// something. Having the model return coordinates and animate a cursor to them
/// was considered and rejected — it serves tutoring rather than this app's
/// purpose, and needs multi-monitor coordinate mapping this does not.
@MainActor
final class RegionSelector {
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<CGRect?, Never>?

    /// Returns the selection in global screen coordinates, or nil if cancelled.
    func selectRegion(on screen: NSScreen) async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(on: screen)
        }
    }

    private func present(on screen: NSScreen) {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = false

        let view = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] rect in
            // The view reports in its own coordinates; callers think in global
            // screen space, which is also what NSScreen.frame uses.
            let global = rect.map {
                CGRect(x: screen.frame.minX + $0.minX,
                       y: screen.frame.minY + $0.minY,
                       width: $0.width,
                       height: $0.height)
            }
            self?.finish(with: global)
        }

        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(view)

        self.panel = panel
    }

    private func finish(with rect: CGRect?) {
        panel?.orderOut(nil)
        panel = nil

        // A stray click produces a degenerate rectangle; treat it as a cancel
        // rather than cropping the screenshot down to nothing.
        let usable = rect.flatMap { $0.width >= 12 && $0.height >= 12 ? $0 : nil }

        continuation?.resume(returning: usable)
        continuation = nil
    }
}

/// Draws the dimmed backdrop and the live selection rectangle.
private final class RegionSelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?

    private var anchor: NSPoint?
    private var current: NSRect = .zero

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard current != .zero else { return }

        // Punch the selection out of the dimming so the user sees the real
        // pixels they are choosing, not a tinted approximation.
        NSColor.clear.setFill()
        current.fill(using: .copy)

        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: current)
        outline.lineWidth = 2
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        current = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        current = NSRect(x: min(anchor.x, point.x),
                         y: min(anchor.y, point.y),
                         width: abs(point.x - anchor.x),
                         height: abs(point.y - anchor.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            anchor = nil
            current = .zero
        }
        onFinish?(current == .zero ? nil : current)
    }

    override func keyDown(with event: NSEvent) {
        // 53 is Escape. Cancelling has to be possible without committing to a
        // drag, so it is handled here rather than on mouse-up.
        if event.keyCode == 53 {
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
