import AppKit

/// Borderless floating panel that can take keystrokes without pulling the whole
/// app forward, and that rides along across Spaces and full-screen apps.
final class CompanionPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init(contentRect: NSRect) {
        // `.resizable` carries no visible affordance on a borderless panel, but
        // without it AppKit refuses the content-driven resizes that let the
        // panel grow with the answer.
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView, .resizable],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit resizes windows about their bottom-left corner, so an answer
    /// streaming in would walk the panel up the screen and away from the cursor
    /// it was summoned next to. Pinning the top-left makes it grow downward.
    override func setContentSize(_ size: NSSize) {
        let top = NSPoint(x: frame.minX, y: frame.maxY)
        super.setContentSize(size)
        setFrameTopLeftPoint(top)
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}
