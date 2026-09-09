import AppKit
import SwiftUI

/// The marks a lesson step draws on the screen it is teaching about.
///
/// Where `ScreenHighlight` is one box that appears and goes away,, this is a
/// standing layer that changes as the lesson advances: the current step's
/// anchors are boxed and numbered, and the steps already covered stay behind as
/// faint outlines so the walk through is visible as a whole rather than one
/// frame at a time.
///
/// A full-screen window rather than one sized to each box, because several
/// marks are on screen at once and their numbers sit outside them. It is
/// click-through and belongs to this app, so it neither takes the click the
/// user is about to make nor appears in this app's own screenshots.
@MainActor
final class LessonOverlay {
    /// Room for a box to sit outside the glyphs rather than clipping them.
    /// The same figure `ScreenHighlight` uses, so a lesson box and a ⌘P box
    /// around the same words are the same size.
    private static let padding: CGFloat = 7

    private var window: NSPanel?

    /// - Parameters:
    ///   - current: Boxes for the step showing now, in the order Max named them.
    ///   - covered: Boxes from earlier steps, drawn faintly.
    ///   - number: The step's position in the lesson, shown on its first box.
    ///   - screen: The area the marks are measured against.
    func show(current: [CGRect], covered: [CGRect], number: Int, on screen: CGRect) {
        guard !current.isEmpty || !covered.isEmpty else {
            hide()
            return
        }

        let window = existingWindow()
        window.setFrame(screen, display: true)

        // AppKit measures from the bottom left and SwiftUI from the top left,
        // so every rect crosses that boundary here rather than in the view,
        // which then deals only in its own coordinates.
        let marks = LessonMarksView(
            current: current.map { flipped($0, in: screen) },
            covered: covered.map { flipped($0, in: screen) },
            number: number
        )
        window.contentView = NSHostingView(rootView: marks)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func flipped(_ rect: CGRect, in screen: CGRect) -> CGRect {
        let padded = rect.insetBy(dx: -Self.padding, dy: -Self.padding)
        return CGRect(x: padded.minX - screen.minX,
                      y: screen.maxY - padded.maxY,
                      width: padded.width,
                      height: padded.height)
    }

    private func existingWindow() -> NSPanel {
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
        // The user is meant to keep working underneath this, which is the whole
        // reason the layer is transparent rather than a board.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window = panel
        return panel
    }
}

private struct LessonMarksView: View {
    let current: [CGRect]
    let covered: [CGRect]
    let number: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Nothing is drawn over the screen itself. A scrim here would make
            // the code underneath harder to read, which is the code the lesson
            // is about.
            Color.clear

            ForEach(Array(covered.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .strokeBorder(DS.Pointer.mark.opacity(0.28), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }

            ForEach(Array(current.enumerated()), id: \.offset) { index, rect in
                mark(rect, isFirst: index == 0)
            }
        }
        .ignoresSafeArea()
    }

    private func mark(_ rect: CGRect, isFirst: Bool) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.chip)
            .strokeBorder(DS.Pointer.mark, lineWidth: 2.5)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .fill(DS.Pointer.mark.opacity(DS.Alpha.hairline))
            )
            // Only the first box of a step is numbered. Numbering all of them
            // would say there are four steps when there is one step about four
            // things.
            .overlay(alignment: .topLeading) {
                if isFirst { badge.offset(x: -9, y: -9) }
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    private var badge: some View {
        Text("\(number)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(DS.Pointer.mark))
            .shadow(radius: 2)
    }
}
