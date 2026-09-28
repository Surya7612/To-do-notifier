import AppKit
import SwiftUI

/// Floating grid board Max draws on while teaching or explaining.
///
/// Its own window rather than marks on the user's display — invented geometry
/// has nowhere to anchor in OCR, which is why PLAN Phase 11 kept diagrams off
/// the lesson overlay. Belonging to this app also excludes it from captures.
@MainActor
final class BoardPanelController {
    private static let panelSize = NSSize(width: 452, height: 500)

    private var panel: NSPanel?
    private var hosting: NSHostingController<BoardView>?

    private(set) var isVisible: Bool = false

    var onClose: (() -> Void)?

    func show(scene: BoardScene, frameIndex: Int) {
        let root = BoardView(scene: scene, frameIndex: frameIndex) { [weak self] in
            self?.onClose?()
            self?.hide()
        }

        if let hosting {
            hosting.rootView = root
        } else {
            let controller = NSHostingController(rootView: root)
            hosting = controller

            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: Self.panelSize),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.contentViewController = controller
            panel.setContentSize(Self.panelSize)
            self.panel = panel
        }

        guard let panel else { return }
        if !isVisible {
            panel.setFrameOrigin(preferredOrigin(for: panel.frame.size))
        }
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func update(scene: BoardScene, frameIndex: Int) {
        guard isVisible else {
            show(scene: scene, frameIndex: frameIndex)
            return
        }
        hosting?.rootView = BoardView(scene: scene, frameIndex: frameIndex) { [weak self] in
            self?.onClose?()
            self?.hide()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    /// Upper-right of the visible frame of the screen under the mouse, so the
    /// board sits next to work rather than on top of the companion panel.
    private func preferredOrigin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 24
        let x = bounds.maxX - size.width - margin
        let y = bounds.maxY - size.height - margin
        return NSPoint(x: max(bounds.minX + margin, x),
                       y: max(bounds.minY + margin, y))
    }
}
