import AppKit

/// Borderless floating panel that can take keystrokes without pulling the whole
/// app forward, and that rides along across Spaces and full-screen apps.
final class CompanionPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init(contentRect: NSRect) {
        // `.resizable` carries no visible affordance on a borderless panel, but
        // without it AppKit refuses the content-driven resizes that let the
        // panel grow with the answer.
        //
        // `.fullSizeContentView` is deliberately absent. It only says where a
        // title bar's content may extend to, and a borderless panel has no
        // title bar — but it still installs the constraints that go with one,
        // which is a reported ingredient in self-sizing window recursion.
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless, .resizable],
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
    ///
    /// A resize to the size it already is returns early, and that is not tidy
    /// housekeeping. Each call here changes the window frame *twice* — once for
    /// the size, once to put the corner back — and every frame change posts
    /// `NSWindowDidLayout`, which the hosting view answers by deriving the
    /// content size again. If nothing actually changed, that second pass is
    /// pure re-entry into a layout pass already in progress.
    override func setContentSize(_ size: NSSize) {
        let current = contentRect(forFrameRect: frame).size
        let isUnchanged = abs(size.width - current.width) < 0.5
            && abs(size.height - current.height) < 0.5
        guard !isUnchanged else { return }

        let top = NSPoint(x: frame.minX, y: frame.maxY)
        super.setContentSize(size)
        setFrameTopLeftPoint(top)
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}
