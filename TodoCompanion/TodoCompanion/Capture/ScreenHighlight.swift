import AppKit
import SwiftUI

/// A frame drawn briefly around the thing Max named.
///
/// It shows where to look and stops there. Flying the cursor to the control, as
/// Clicky does, would be inference acting rather than suggesting, needs
/// Accessibility permission this app declines to require, and fights anyone who
/// happens to be mid-drag.
///
/// The window belongs to this app, so `ScreenCapture` already excludes it from
/// screenshots along with the panel and the cursor ring.
@MainActor
final class ScreenHighlight {
    /// Room for the box to sit outside the glyphs rather than clipping them.
    private static let padding: CGFloat = 7

    /// Long enough to follow it with your eyes, short enough that it is gone
    /// before it becomes something to dismiss.
    private static let visible: TimeInterval = 2.4

    private var window: NSWindow?
    private var pendingHide: Task<Void, Never>?

    /// - Parameter untilHidden: Leaves the box up rather than fading it out.
    ///
    ///   For the follow-along highlight, where the box moves from one control
    ///   to the next as Max names them and is taken down when the voice stops.
    ///   A timeout there would blink the box out mid-sentence, since a clause
    ///   takes longer to say than the box is otherwise worth leaving up.
    func show(_ rect: CGRect, untilHidden: Bool = false) {
        pendingHide?.cancel()
        pendingHide = nil

        let framed = rect.insetBy(dx: -Self.padding, dy: -Self.padding)
        guard framed.width > 0, framed.height > 0 else { return }

        let window = existingWindow()
        // Animated, because this now moves between controls rather than only
        // appearing: a box that jumps is a second box as far as the eye is
        // concerned, where one that travels is plainly the same one.
        window.setFrame(framed, display: true, animate: window.isVisible)
        window.orderFrontRegardless()

        guard !untilHidden else { return }

        pendingHide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.visible))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        pendingHide?.cancel()
        pendingHide = nil
        window?.orderOut(nil)
    }

    private func existingWindow() -> NSWindow {
        if let window { return window }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        // The point is to indicate a control the user is about to use, so the
        // overlay must not be the thing that receives the click.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: HighlightBoxView())
        window = panel
        return panel
    }
}

private struct HighlightBoxView: View {
    @State private var settled = false

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.chip)
            .strokeBorder(DS.Status.saved, lineWidth: 2.5)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .fill(DS.Status.saved.opacity(DS.Alpha.hairline))
            )
            // Starts slightly large and settles, which draws the eye to it the
            // way a static box does not.
            .scaleEffect(settled ? 1 : 1.12)
            .opacity(settled ? 1 : 0)
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: settled)
            .onAppear { settled = true }
            .onDisappear { settled = false }
    }
}
