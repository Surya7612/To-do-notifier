import AppKit
import SwiftUI

/// Floating grid board Max draws on while teaching or explaining.
///
/// Its own window rather than marks on the user's display — invented geometry
/// has nowhere to anchor in OCR. Resizable. Drag uses a real AppKit title strip
/// because SwiftUI hosting views swallow `isMovableByWindowBackground`.
@MainActor
final class BoardPanelController {
    private static let defaultSize = NSSize(width: 560, height: 620)
    private static let minimumSize = NSSize(width: 380, height: 420)
    private static let dragStripHeight: CGFloat = 44

    private var panel: BoardPanel?
    private var hosting: NSHostingController<BoardView>?
    private var dragStrip: BoardDragStrip?
    /// Bumps every publish so the pen timeline restarts even when frame index repeats.
    private var sketchNonce = 0

    private(set) var isVisible: Bool = false

    /// The cut currently drawn, so the next cut of the same scene keeps it.
    private var shownScene: BoardScene?
    private var shownFrame: BoardScene.Frame?

    var onClose: (() -> Void)?

    private func makeRoot(scene: BoardScene, frameIndex: Int, narration: String?) -> BoardView {
        sketchNonce += 1
        let polished = scene.polishedForDisplay()
        let previous = shownScene == scene ? shownFrame : nil
        let current = polished.frames.isEmpty ? nil : polished.frames[polished.clampedFrameIndex(frameIndex)]
        shownScene = scene
        shownFrame = current
        return BoardView(scene: polished, frameIndex: frameIndex,
                         previousFrame: previous, narration: narration,
                         sketchReveal: true, sketchNonce: sketchNonce) { [weak self] in
            self?.onClose?()
            self?.hide()
        }
    }

    func show(scene: BoardScene, frameIndex: Int, narration: String?) {
        let root = makeRoot(scene: scene, frameIndex: frameIndex, narration: narration)

        if let hosting {
            hosting.rootView = root
        } else {
            let controller = NSHostingController(rootView: root)
            hosting = controller

            let panel = BoardPanel(
                contentRect: NSRect(origin: .zero, size: Self.defaultSize)
            )
            panel.minSize = Self.minimumSize
            panel.contentMinSize = Self.minimumSize

            let container = NSView(frame: NSRect(origin: .zero, size: Self.defaultSize))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.clear.cgColor

            controller.view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(controller.view)
            NSLayoutConstraint.activate([
                controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                controller.view.topAnchor.constraint(equalTo: container.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            // AppKit strip on top of SwiftUI — the only hit target that reliably
            // starts a window drag on a non-activating floating panel.
            let strip = BoardDragStrip(frame: .zero)
            strip.translatesAutoresizingMaskIntoConstraints = false
            strip.onClose = { [weak self] in
                self?.onClose?()
                self?.hide()
            }
            container.addSubview(strip)
            NSLayoutConstraint.activate([
                strip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                strip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                strip.topAnchor.constraint(equalTo: container.topAnchor),
                strip.heightAnchor.constraint(equalToConstant: Self.dragStripHeight),
            ])
            dragStrip = strip

            panel.contentView = container
            panel.setContentSize(Self.defaultSize)
            self.panel = panel
        }

        guard let panel else { return }
        if !isVisible {
            let size = panel.frame.size.width > 1 ? panel.frame.size : Self.defaultSize
            panel.setFrameOrigin(preferredOrigin(for: size))
        }
        panel.orderFrontRegardless()
        isVisible = true
    }

    func update(scene: BoardScene, frameIndex: Int, narration: String?) {
        guard isVisible else {
            show(scene: scene, frameIndex: frameIndex, narration: narration)
            return
        }
        hosting?.rootView = makeRoot(scene: scene, frameIndex: frameIndex, narration: narration)
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        shownScene = nil
        shownFrame = nil
    }

    /// Opposite the mouse horizontally so a right-side editor gets a left board.
    private func preferredOrigin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 20
        let placeOnLeft = mouse.x > bounds.midX
        let x = placeOnLeft
            ? bounds.minX + margin
            : bounds.maxX - size.width - margin
        let y = bounds.maxY - size.height - margin
        return NSPoint(x: max(bounds.minX + margin, min(x, bounds.maxX - size.width - margin)),
                       y: max(bounds.minY + margin, y))
    }
}

/// Non-activating floating panel that can still become key so drag works.
private final class BoardPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = true
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Title-bar strip that owns mouse-down for window dragging.
private final class BoardDragStrip: NSView {
    var onClose: (() -> Void)?
    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: "Close the board")
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 4),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if closeButton.frame.contains(local) {
            closeButton.performClick(nil)
            return
        }
        window?.makeKeyAndOrderFront(nil)
        window?.performDrag(with: event)
    }

    @objc private func closeClicked() {
        onClose?()
    }
}
