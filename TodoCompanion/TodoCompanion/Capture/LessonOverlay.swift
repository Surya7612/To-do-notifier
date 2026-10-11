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
/// A step with nothing Vision can box still draws a short cue (the quoted label
/// or a clipped tip) and its number — never the full spoken sentence, which
/// hid the user's work and only duplicated the panel. Skipping the update left
/// the previous step's boxes stranded while the panel said a different step.
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
    ///   - caption: Short cue beside a miss / conceptual step. Empty when the
    ///     box itself is the cue — teachers point; they do not re-paste the talk.
    ///   - isConnected: Whether to run an arrow from each box to the next.
    ///   - screen: The area the marks are measured against.
    func show(current: [CGRect],
              covered: [CGRect],
              number: Int,
              caption: String,
              isConnected: Bool,
              on screen: CGRect) {
        if current.isEmpty && covered.isEmpty && caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            number: number,
            caption: caption,
            isConnected: isConnected,
            bounds: CGSize(width: screen.width, height: screen.height)
        )
        window.contentView = NSHostingView(rootView: marks)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        window?.contentView = nil
        window?.close()
        window = nil
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
    let caption: String
    let isConnected: Bool
    let bounds: CGSize

    /// How far the caption sits below the box it belongs to.
    private static let captionDrop: CGFloat = 8

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

            if isConnected, current.count > 1 { connectors }

            ForEach(Array(current.enumerated()), id: \.offset) { index, rect in
                mark(rect, isFirst: index == 0)
            }

            if !caption.isEmpty {
                captionChip.offset(x: captionPlacement.x, y: captionPlacement.y)
            }
            // No lone floating badge: the panel already says "Step N of M", and
            // a number over empty air (often Max itself) reads as a miss.
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

    /// A tiny name-tag for what the tutor is pointing at when Vision missed —
    /// one line, narrow, so it cannot blanket the code underneath.
    private var captionChip: some View {
        HStack(alignment: .center, spacing: 6) {
            if current.isEmpty { badge }
            Text(caption)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .strokeBorder(DS.Pointer.mark.opacity(0.55))
                )
        )
        .shadow(radius: 3, y: 1)
    }

    /// Beside the first box when there is one; otherwise a tip floating near
    /// the last covered mark, or over the working area of the capture.
    private var captionPlacement: CGPoint {
        if let anchor = current.first {
            return captionOrigin(under: anchor)
        }
        return floatingOrigin
    }

    /// A conceptual step with no OCR hit still has to land somewhere readable.
    /// Prefer the last covered box so the tip follows the walk; otherwise sit
    /// over the *left* third of the capture (problem statement on LeetCode-
    /// shaped layouts) — middle-right put the tip on Max's own panel.
    private var floatingOrigin: CGPoint {
        if let last = covered.last {
            return captionOrigin(under: last)
        }
        let estimatedHeight: CGFloat = 28
        let x = min(max(bounds.width * 0.08, 16), max(16, bounds.width - 200))
        let y = min(max(bounds.height * 0.36, 16), max(16, bounds.height - estimatedHeight - 16))
        return CGPoint(x: x, y: y)
    }

    /// Below the box, or above it when the box is near the bottom of the
    /// screen. A cue clipped off the edge is the one place this can fail
    /// silently, since the user cannot tell it was ever drawn.
    private func captionOrigin(under rect: CGRect) -> CGPoint {
        let estimatedHeight: CGFloat = 28
        let below = rect.maxY + Self.captionDrop
        let fits = below + estimatedHeight < bounds.height

        return CGPoint(x: min(rect.minX, max(0, bounds.width - 200)),
                       y: fits ? below : max(0, rect.minY - estimatedHeight - Self.captionDrop))
    }

    /// Arrows from each box to the next, drawn only when Max wrote one.
    private var connectors: some View {
        Canvas { context, _ in
            for (from, to) in zip(current, current.dropFirst()) {
                context.stroke(Self.arrow(from: from, to: to),
                               with: .color(DS.Pointer.mark),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// A line between the nearest edges of two boxes, with a head on the end.
    ///
    /// Edge to edge rather than centre to centre, so the line does not strike
    /// through the very words it is joining.
    private static func arrow(from: CGRect, to: CGRect) -> Path {
        let start = CGPoint(x: from.midX, y: from.maxY < to.minY ? from.maxY : from.midY)
        let end = CGPoint(x: to.midX, y: from.maxY < to.minY ? to.minY : to.midY)

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let head: CGFloat = 7
        for sweep in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x + head * cos(angle + sweep),
                                     y: end.y + head * sin(angle + sweep)))
        }

        return path
    }
}
