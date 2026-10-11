import AppKit
import SwiftUI

/// Hit target that starts an AppKit window drag.
///
/// SwiftUI hosting views swallow mouse events, so `isMovableByWindowBackground`
/// alone often does nothing on a borderless panel. This view calls
/// `performDrag(with:)` the way a real title bar does.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}
