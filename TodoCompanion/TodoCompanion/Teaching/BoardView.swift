import AppKit
import SwiftUI

/// Graph-paper teaching surface Max draws a `BoardScene` onto.
///
/// Opaque paper (not a translucent overlay): the same contrast rule as the
/// panel's code well and lesson captions — text whose brightness comes from
/// the wallpaper is text nobody can read.
///
/// Each frame is drawn stroke by stroke along the real outline, with the pen
/// at the end of the stroke, in the order `SketchTimeline` gives — which is
/// the order the narration names things. What the previous cut already drew
/// stays put rather than being wiped and redrawn.
struct BoardView: View {
    let scene: BoardScene
    let frameIndex: Int
    /// The cut on screen before this one, so what it drew is not redrawn.
    var previousFrame: BoardScene.Frame?
    /// What Max says over this cut; paces the pen and orders the strokes.
    var narration: String?
    var sketchReveal: Bool = true
    /// Changes whenever the controller republishes so the pen restarts.
    var sketchNonce: Int = 0
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                let side = max(280, min(geo.size.width, geo.size.height))
                ZStack {
                    BoardPaper()
                    SketchBoardCanvas(
                        frame: currentFrame,
                        previous: previousFrame,
                        narration: narration,
                        frameIndex: frameIndex,
                        sketchNonce: sketchNonce,
                        animate: sketchReveal
                    )
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(DS.Spacing.normal)
        }
        .frame(minWidth: 360, minHeight: 400)
        // Leave the top strip clear for the AppKit drag handle overlay.
        .padding(.top, 4)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        )
    }

    private var currentFrame: BoardScene.Frame {
        guard !scene.frames.isEmpty else {
            return BoardScene.Frame(step: nil, shapes: [])
        }
        return scene.frames[scene.clampedFrameIndex(frameIndex)]
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.tight) {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .help("Drag the top of the board to move it")
                .accessibilityLabel("Drag board")
            Text(scene.title ?? "Board")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: DS.Spacing.tight)
            if scene.frames.count > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<scene.frames.count, id: \.self) { index in
                        Capsule()
                            .fill(index == scene.clampedFrameIndex(frameIndex)
                                  ? Color.boardInkAccent
                                  : Color.primary.opacity(index < frameIndex ? 0.35 : 0.12))
                            .frame(width: index == scene.clampedFrameIndex(frameIndex) ? 14 : 6, height: 6)
                    }
                }
                .accessibilityLabel("Cut \(scene.clampedFrameIndex(frameIndex) + 1) of \(scene.frames.count)")
            }
            // Close lives on the AppKit drag strip so hits are not swallowed.
            Color.clear.frame(width: 22, height: 22)
        }
        .padding(.horizontal, DS.Spacing.normal)
        .padding(.top, DS.Spacing.normal)
        .padding(.bottom, DS.Spacing.tight)
        .contentShape(Rectangle())
    }
}

/// Faint graph-paper behind the shapes.
private struct BoardPaper: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(nsColor: .textBackgroundColor)))

            let step: CGFloat = 20
            var grid = Path()
            var x: CGFloat = 0
            while x <= size.width {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(grid, with: .color(Color.primary.opacity(0.06)), lineWidth: 1)
        }
    }
}

/// One frame, drawn along `SketchTimeline` with a pen.
private struct SketchBoardCanvas: View {
    let frame: BoardScene.Frame
    let previous: BoardScene.Frame?
    let narration: String?
    let frameIndex: Int
    let sketchNonce: Int
    let animate: Bool

    private var duration: TimeInterval {
        SketchTimeline.duration(for: frame, previous: previous, narration: narration)
    }

    private var reveals: [SketchTimeline.Reveal] {
        SketchTimeline.reveals(for: frame, previous: previous, narration: narration)
    }

    private var clockKey: Int { frameIndex &* 1_000 &+ sketchNonce }

    var body: some View {
        let reveals = self.reveals
        let duration = self.duration
        TimelineView(.animation(minimumInterval: 1 / 45, paused: !animate)) { timeline in
            let fraction = animate
                ? SketchRevealClock.progress(for: clockKey, at: timeline.date, duration: duration)
                : 1
            Canvas { context, size in
                var painter = SketchPainter(context: context, size: size, frame: frame)
                painter.draw(reveals: reveals, at: fraction)
            }
        }
        .onChange(of: clockKey) { _, newValue in
            SketchRevealClock.reset(key: newValue)
        }
        .onAppear {
            SketchRevealClock.reset(key: clockKey)
        }
    }
}

/// Immediate-mode drawing of one frame at one moment of its timeline.
private struct SketchPainter {
    var context: GraphicsContext
    let size: CGSize
    let frame: BoardScene.Frame
    private let rects: [String: CGRect]
    private var pen: CGPoint?

    init(context: GraphicsContext, size: CGSize, frame: BoardScene.Frame) {
        self.context = context
        self.size = size
        self.frame = frame
        var rects: [String: CGRect] = [:]
        for shape in frame.shapes {
            if let id = shape.identifier, let rect = Self.rect(of: shape, in: size) {
                rects[id] = rect
            }
        }
        self.rects = rects
    }

    mutating func draw(reveals: [SketchTimeline.Reveal], at fraction: Double) {
        // Washes and arrays sit under links; text sits over everything.
        let layers: [(BoardScene.Shape) -> Bool] = [
            { if case .mark(_, .highlight, _) = $0 { return true }; return false },
            { $0.isBody },
            { $0.isLink },
            { if case .mark(_, let style, _) = $0 { return style != .highlight }; return false },
            { $0.isWords },
        ]
        for layer in layers {
            for (index, shape) in frame.shapes.enumerated() where layer(shape) {
                let reveal = reveals.indices.contains(index) ? reveals[index] : .carried
                let t = CGFloat(reveal.progress(at: fraction))
                guard t > 0 else { continue }
                let relabel: Bool = { if case .relabel = reveal { return true }; return false }()
                draw(shape, index: index, t: t, relabel: relabel)
            }
        }
        if let pen { drawPen(at: pen) }
    }

    // MARK: Shapes

    private mutating func draw(_ shape: BoardScene.Shape, index: Int, t: CGFloat, relabel: Bool) {
        let seed = SketchInk.seed(shape.identifier ?? "\(index)")
        switch shape {
        case let .rect(_, _, _, _, _, color, label),
             let .ellipse(_, _, _, _, _, color, label),
             let .circle(_, _, _, _, color, label):
            guard let rect = Self.rect(of: shape, in: size) else { return }
            let outline: Path = {
                if case .rect = shape { return SketchInk.rect(rect, seed: seed) }
                return SketchInk.ellipse(rect, seed: seed)
            }()
            let strokeT = relabel ? 1 : min(1, t / 0.7)
            stroke(outline, upTo: strokeT, color: Self.ink(color), width: 2.4)
            if let wash = Self.wash(color) {
                let fill: Path = {
                    if case .rect = shape { return Path(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 5) }
                    return Path(ellipseIn: rect.insetBy(dx: 2, dy: 2))
                }()
                var washed = context
                washed.opacity = Double(min(1, max(0, (strokeT - 0.3) / 0.5)))
                washed.fill(fill, with: .color(wash.opacity(0.2)))
            }
            if let label {
                let labelT = relabel ? t : max(0, (t - 0.65) / 0.35)
                write(label, centeredIn: rect, t: labelT,
                      font: .system(size: Self.fontSize(for: rect, text: label), weight: .semibold, design: .rounded),
                      color: Color.boardInk)
            }

        case let .icon(_, _, _, _, _, pictogram, color, _):
            guard let rect = Self.rect(of: shape, in: size) else { return }
            var cg = CGMutablePath()
            pictogram.add(to: &cg, in: rect)
            if let wash = Self.wash(color) {
                var washed = context
                washed.opacity = Double(t)
                washed.fill(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)),
                            with: .color(wash.opacity(0.14)))
            }
            stroke(Path(cg), upTo: relabel ? 1 : t, color: Self.ink(color), width: 2.4)

        case let .array(_, _, _, _, _, values, highlight, pointers, color, label):
            guard let rect = Self.rect(of: shape, in: size) else { return }
            drawArray(rect: rect, values: values, highlight: highlight, pointers: pointers,
                      color: color, label: label, t: t, relabel: relabel, seed: seed)

        case let .bubble(_, _, _, _, _, text, color):
            guard let rect = Self.rect(of: shape, in: size) else { return }
            let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.78)
            var outline = SketchInk.rect(body, seed: seed)
            outline.move(to: CGPoint(x: body.minX + body.width * 0.18, y: body.maxY))
            outline.addLine(to: CGPoint(x: body.minX + body.width * 0.22, y: rect.maxY))
            outline.addLine(to: CGPoint(x: body.minX + body.width * 0.32, y: body.maxY))
            var paper = context
            paper.opacity = Double(min(1, t * 2))
            paper.fill(Path(roundedRect: body, cornerRadius: 8),
                       with: .color(Color(nsColor: .textBackgroundColor).opacity(0.96)))
            stroke(outline, upTo: relabel ? 1 : min(1, t / 0.55), color: Self.ink(color), width: 2.1)
            write(text, centeredIn: body.insetBy(dx: 6, dy: 2),
                  t: relabel ? t : max(0, (t - 0.45) / 0.55),
                  font: Self.handwriting(size: 14), color: Self.ink(color))

        case let .arrow(from, to, color, label):
            guard let (a, b) = endpoints(from, to) else { return }
            let curve = SketchInk.curve(from: a, to: b, seed: seed)
            let strokeT = min(1, t / 0.85)
            stroke(curve.path, upTo: strokeT, color: Self.ink(color).opacity(0.85), width: 2.3)
            if strokeT >= 1 { drawArrowHead(at: b, from: curve.control, color: Self.ink(color)) }
            if let label {
                write(label, centeredAt: curve.midpoint(lift: 12),
                      t: max(0, (t - 0.55) / 0.45),
                      font: Self.handwriting(size: 12), color: Color.secondary, maxWidth: 120)
            }

        case let .line(from, to, color):
            guard let (a, b) = endpoints(from, to) else { return }
            stroke(SketchInk.curve(from: a, to: b, seed: seed).path, upTo: t,
                   color: Self.ink(color).opacity(0.7), width: 2)

        case let .mark(target, style, color):
            guard let rect = rects[target] else { return }
            drawMark(style, around: rect, color: color, t: t, seed: seed)

        case let .path(points, color, label):
            let mapped = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            let path = SketchInk.smooth(through: mapped)
            stroke(path, upTo: t, color: Self.ink(color == .primary ? .accent : color), width: 2.6)
            if let label, let last = mapped.last {
                write(label, centeredAt: CGPoint(x: last.x, y: last.y - 14),
                      t: max(0, (t - 0.8) / 0.2),
                      font: Self.handwriting(size: 13), color: Color.boardInk, maxWidth: 140)
            }

        case let .text(x, y, text, color):
            drawTip(text, at: CGPoint(x: x * size.width, y: y * size.height),
                    emphasis: color == .emphasis || color == .accent, t: t)

        case let .label(x, y, text, _):
            drawChip(text, at: CGPoint(x: x * size.width, y: y * size.height), t: t)
        }
    }

    private mutating func drawArray(rect: CGRect, values: [String], highlight: [Int],
                                    pointers: [BoardScene.Shape.Pointer],
                                    color: BoardScene.ColorToken, label: String?,
                                    t: CGFloat, relabel: Bool, seed: UInt64) {
        let count = max(values.count, 1)
        let cell = rect.width / CGFloat(count)
        var grid = SketchInk.rect(rect, seed: seed)
        for index in 1..<count {
            let x = rect.minX + CGFloat(index) * cell
            grid.move(to: CGPoint(x: x, y: rect.minY + 1))
            grid.addLine(to: CGPoint(x: x + 0.6, y: rect.maxY - 1))
        }
        let gridT = relabel ? 1 : min(1, t / 0.5)

        let highlightColor = Self.wash(color) ?? Color.boardInkAccent
        for index in highlight {
            var washed = context
            washed.opacity = Double(min(1, max(0, (t - 0.45) / 0.3)))
            washed.fill(Path(CGRect(x: rect.minX + CGFloat(index) * cell + 2, y: rect.minY + 2,
                                    width: cell - 4, height: rect.height - 4)),
                        with: .color(highlightColor.opacity(0.32)))
        }
        stroke(grid, upTo: gridT, color: Color.boardInk, width: 2.2)

        let fontSize = min(18, max(10, min(cell * 0.45, rect.height * 0.5)))
        for (index, value) in values.enumerated() {
            let cellRect = CGRect(x: rect.minX + CGFloat(index) * cell, y: rect.minY,
                                  width: cell, height: rect.height)
            let start = 0.35 + 0.5 * CGFloat(index) / CGFloat(count)
            let local = relabel ? t : max(0, (t - start) / 0.15)
            write(value, centeredIn: cellRect, t: local,
                  font: .system(size: fontSize, weight: .semibold, design: .monospaced),
                  color: Color.boardInk)
            var numbering = context
            numbering.opacity = Double(min(1, local)) * 0.55
            numbering.draw(Text("\(index)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary),
                           at: CGPoint(x: cellRect.midX, y: rect.minY - 7), anchor: .center)
        }

        let pointerT = max(0, (t - 0.8) / 0.2)
        if pointerT > 0 {
            var byIndex: [Int: [String]] = [:]
            for pointer in pointers { byIndex[pointer.index, default: []].append(pointer.name) }
            for (index, names) in byIndex {
                let x = rect.minX + (CGFloat(index) + 0.5) * cell
                var arrow = Path()
                arrow.move(to: CGPoint(x: x, y: rect.maxY + 18))
                arrow.addLine(to: CGPoint(x: x, y: rect.maxY + 4))
                arrow.move(to: CGPoint(x: x - 4, y: rect.maxY + 9))
                arrow.addLine(to: CGPoint(x: x, y: rect.maxY + 4))
                arrow.addLine(to: CGPoint(x: x + 4, y: rect.maxY + 9))
                var local = context
                local.opacity = Double(pointerT)
                local.stroke(arrow, with: .color(Color.boardInkAccent),
                             style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                local.draw(Text(names.joined(separator: ","))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.boardInkAccent),
                           at: CGPoint(x: x, y: rect.maxY + 28), anchor: .center)
            }
        }

        if let label {
            var local = context
            local.opacity = Double(min(1, t * 2))
            local.draw(Text(label).font(Self.handwriting(size: 13)).foregroundColor(.secondary),
                       at: CGPoint(x: rect.minX, y: rect.minY - 20), anchor: .leading)
        }
    }

    private mutating func drawMark(_ style: BoardScene.Shape.MarkStyle, around rect: CGRect,
                                   color: BoardScene.ColorToken, t: CGFloat, seed: UInt64) {
        switch style {
        case .circle:
            let ring = SketchInk.ellipse(rect.insetBy(dx: -12, dy: -10), seed: seed &+ 7)
            stroke(ring, upTo: t, color: Self.markInk(color, fallback: Color.boardInkAccent), width: 3)
        case .underline:
            var path = Path()
            let y = rect.maxY + 6
            path.move(to: CGPoint(x: rect.minX - 4, y: y))
            path.addQuadCurve(to: CGPoint(x: rect.maxX + 4, y: y + 2),
                              control: CGPoint(x: rect.midX, y: y + 5))
            stroke(path, upTo: t, color: Self.markInk(color, fallback: Color.boardInkAccent), width: 3)
        case .cross:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 4, y: rect.minY + 4))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY - 4))
            path.move(to: CGPoint(x: rect.maxX - 4, y: rect.minY + 4))
            path.addLine(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 4))
            stroke(path, upTo: t, color: Self.markInk(color, fallback: Color.boardProblem), width: 3)
        case .check:
            let s = min(22, rect.height * 0.6)
            let origin = CGPoint(x: rect.maxX - s * 0.4, y: rect.minY - s * 0.5)
            var path = Path()
            path.move(to: CGPoint(x: origin.x, y: origin.y + s * 0.55))
            path.addLine(to: CGPoint(x: origin.x + s * 0.35, y: origin.y + s * 0.9))
            path.addLine(to: CGPoint(x: origin.x + s, y: origin.y))
            stroke(path, upTo: t, color: Self.markInk(color, fallback: Color.boardSuccess), width: 3.2)
        case .highlight:
            var washed = context
            washed.opacity = Double(t)
            washed.fill(Path(roundedRect: rect.insetBy(dx: -6, dy: -6), cornerRadius: 8),
                        with: .color((Self.wash(color) ?? Color.boardInkAccent).opacity(0.28)))
        }
    }

    // MARK: Words

    private mutating func drawTip(_ text: String, at center: CGPoint, emphasis: Bool, t: CGFloat) {
        let resolved = context.resolve(Text(text)
            .font(Self.handwriting(size: 17))
            .foregroundColor(Color.boardInk))
        let measured = resolved.measure(in: CGSize(width: min(size.width * 0.86, 360), height: 120))
        let box = CGRect(x: center.x - measured.width / 2 - 10, y: center.y - measured.height / 2 - 6,
                         width: measured.width + 20, height: measured.height + 12)
        var card = context
        card.opacity = Double(min(1, t * 3))
        card.fill(Path(roundedRect: box, cornerRadius: 8),
                  with: .color(Color(nsColor: .textBackgroundColor).opacity(0.95)))
        if emphasis {
            card.stroke(Path(roundedRect: box, cornerRadius: 8),
                        with: .color(Color.boardInkAccent.opacity(0.6)), lineWidth: 1.5)
        }
        reveal(resolved, in: box.insetBy(dx: 10, dy: 6), t: t)
    }

    private mutating func drawChip(_ text: String, at center: CGPoint, t: CGFloat) {
        let resolved = context.resolve(Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary))
        let measured = resolved.measure(in: CGSize(width: 120, height: 30))
        let box = CGRect(x: center.x - measured.width / 2 - 6, y: center.y - measured.height / 2 - 2,
                         width: measured.width + 12, height: measured.height + 4)
        var chip = context
        chip.opacity = Double(min(1, t * 2))
        chip.fill(Path(roundedRect: box, cornerRadius: box.height / 2),
                  with: .color(Color(nsColor: .textBackgroundColor).opacity(0.95)))
        chip.stroke(Path(roundedRect: box, cornerRadius: box.height / 2),
                    with: .color(Color.boardInk.opacity(0.25)), lineWidth: 1)
        reveal(resolved, in: box.insetBy(dx: 6, dy: 2), t: t)
    }

    private mutating func write(_ text: String, centeredIn rect: CGRect, t: CGFloat,
                                font: Font, color: Color) {
        let resolved = context.resolve(Text(text).font(font).foregroundColor(color))
        let measured = resolved.measure(in: CGSize(width: rect.width - 6, height: rect.height))
        let box = CGRect(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2,
                         width: measured.width, height: measured.height)
        reveal(resolved, in: box, t: t)
    }

    private mutating func write(_ text: String, centeredAt point: CGPoint, t: CGFloat,
                                font: Font, color: Color, maxWidth: CGFloat) {
        let resolved = context.resolve(Text(text).font(font).foregroundColor(color))
        let measured = resolved.measure(in: CGSize(width: maxWidth, height: 60))
        let box = CGRect(x: point.x - measured.width / 2, y: point.y - measured.height / 2,
                         width: measured.width, height: measured.height)
        var paper = context
        paper.opacity = Double(min(1, t * 2)) * 0.9
        paper.fill(Path(roundedRect: box.insetBy(dx: -3, dy: -1), cornerRadius: 3),
                   with: .color(Color(nsColor: .textBackgroundColor)))
        reveal(resolved, in: box, t: t)
    }

    /// Text appears left to right, as if being written, with the pen at its edge.
    private mutating func reveal(_ resolved: GraphicsContext.ResolvedText, in box: CGRect, t: CGFloat) {
        guard t > 0 else { return }
        var clipped = context
        clipped.clip(to: Path(CGRect(x: box.minX - 2, y: box.minY - 4,
                                     width: (box.width + 4) * min(1, t), height: box.height + 8)))
        clipped.draw(resolved, in: box)
        if t < 1 {
            pen = CGPoint(x: box.minX + box.width * t, y: box.maxY - 2)
        }
    }

    // MARK: Strokes

    private mutating func stroke(_ path: Path, upTo t: CGFloat, color: Color, width: CGFloat) {
        guard t > 0 else { return }
        let drawn = t >= 1 ? path : path.trimmedPath(from: 0, to: t)
        context.stroke(drawn, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        if t < 1, let point = drawn.currentPoint {
            pen = point
        }
    }

    private func drawArrowHead(at tip: CGPoint, from control: CGPoint, color: Color) {
        let angle = atan2(tip.y - control.y, tip.x - control.x)
        let head: CGFloat = 11
        var path = Path()
        path.move(to: CGPoint(x: tip.x - head * cos(angle - .pi / 7), y: tip.y - head * sin(angle - .pi / 7)))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x - head * cos(angle + .pi / 7), y: tip.y - head * sin(angle + .pi / 7)))
        context.stroke(path, with: .color(color.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
    }

    /// A pencil: the tip where the line is being drawn, the body trailing off.
    private func drawPen(at point: CGPoint) {
        var body = Path()
        body.move(to: point)
        body.addLine(to: CGPoint(x: point.x + 16, y: point.y + 22))
        context.stroke(body, with: .color(Color.boardInkAccent.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                     with: .color(Color.boardInkAccent))
    }

    // MARK: Geometry

    private func endpoints(_ from: BoardScene.Shape.Endpoint,
                           _ to: BoardScene.Shape.Endpoint) -> (CGPoint, CGPoint)? {
        guard let a = endpoint(from, toward: to), let b = endpoint(to, toward: from) else { return nil }
        return (a, b)
    }

    private func endpoint(_ endpoint: BoardScene.Shape.Endpoint,
                          toward other: BoardScene.Shape.Endpoint) -> CGPoint? {
        switch endpoint {
        case let .point(x, y):
            return CGPoint(x: x * size.width, y: y * size.height)
        case let .id(name):
            guard let rect = rects[name] else { return nil }
            let target: CGPoint = {
                switch other {
                case let .point(x, y):
                    return CGPoint(x: x * size.width, y: y * size.height)
                case let .id(otherName):
                    guard let otherRect = rects[otherName] else { return CGPoint(x: rect.midX, y: rect.midY) }
                    return CGPoint(x: otherRect.midX, y: otherRect.midY)
                }
            }()
            return Self.borderPoint(of: rect.insetBy(dx: -4, dy: -4), toward: target)
        }
    }

    /// Where the center→target ray exits the rect — keeps arrows in the gap.
    private static func borderPoint(of rect: CGRect, toward target: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - center.x
        let dy = target.y - center.y
        if abs(dx) < 0.5, abs(dy) < 0.5 { return center }
        let scaleX = abs(dx) > 0.5 ? (rect.width / 2) / abs(dx) : .greatestFiniteMagnitude
        let scaleY = abs(dy) > 0.5 ? (rect.height / 2) / abs(dy) : .greatestFiniteMagnitude
        let t = min(scaleX, scaleY)
        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }

    static func rect(of shape: BoardScene.Shape, in size: CGSize) -> CGRect? {
        if case let .circle(_, x, y, r, _, _) = shape {
            let radius = r * size.width
            return CGRect(x: x * size.width - radius, y: y * size.height - radius,
                          width: radius * 2, height: radius * 2)
        }
        if case let .bubble(_, x, y, w, h, _, _) = shape {
            return CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
        }
        guard let box = shape.footprint else { return nil }
        return CGRect(x: box.x * size.width, y: box.y * size.height,
                      width: box.w * size.width, height: box.h * size.height)
    }

    private static func fontSize(for rect: CGRect, text: String) -> CGFloat {
        let byWidth = rect.width / max(CGFloat(text.count) * 0.58, 1)
        return min(17, max(10, min(byWidth, rect.height * 0.42)))
    }

    private static func handwriting(size: CGFloat) -> Font {
        .custom("Marker Felt", size: size)
    }

    // MARK: Colour

    static func ink(_ token: BoardScene.ColorToken) -> Color {
        switch token {
        case .problem: Color.boardProblem
        case .success: Color.boardSuccess
        default: Color.boardInk
        }
    }

    static func markInk(_ token: BoardScene.ColorToken, fallback: Color) -> Color {
        switch token {
        case .problem: Color.boardProblem
        case .success: Color.boardSuccess
        case .primary, .muted: fallback
        default: wash(token) ?? fallback
        }
    }

    /// The concept colour a shape is washed with. Muted and primary stay paper.
    static func wash(_ token: BoardScene.ColorToken) -> Color? {
        switch token {
        case .oxygen: Color(red: 0.90, green: 0.30, blue: 0.26)
        case .hydrogen: Color(red: 0.26, green: 0.52, blue: 0.95)
        case .carbon: Color(white: 0.45)
        case .nitrogen: Color(red: 0.48, green: 0.36, blue: 0.88)
        case .accent, .emphasis: Color.boardInkAccent
        case .success: Color.boardSuccess
        case .problem: Color.boardProblem
        case .muted, .primary: nil
        }
    }
}

/// Deterministic hand-drawn geometry: the same id wobbles the same way every
/// time it is drawn, so a box carried into the next cut does not shimmer.
private enum SketchInk {
    struct Random {
        var state: UInt64
        mutating func next() -> CGFloat {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return CGFloat(z % 10_000) / 10_000
        }
        mutating func signed() -> CGFloat { next() * 2 - 1 }
    }

    /// FNV-1a — `hashValue` is reseeded per launch, which would change the wobble.
    static func seed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func rect(_ r: CGRect, seed: UInt64) -> Path {
        var random = Random(state: seed)
        let jitter = min(2.4, max(r.width, r.height) * 0.014)
        func wobble(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x + random.signed() * jitter, y: p.y + random.signed() * jitter)
        }
        let corners = [
            wobble(CGPoint(x: r.minX, y: r.minY)), wobble(CGPoint(x: r.maxX, y: r.minY)),
            wobble(CGPoint(x: r.maxX, y: r.maxY)), wobble(CGPoint(x: r.minX, y: r.maxY)),
        ]
        var path = Path()
        path.move(to: corners[0])
        for index in 1...4 {
            let a = corners[index - 1], b = corners[index % 4]
            let mid = CGPoint(x: (a.x + b.x) / 2 + random.signed() * jitter * 1.4,
                              y: (a.y + b.y) / 2 + random.signed() * jitter * 1.4)
            path.addQuadCurve(to: b, control: mid)
        }
        // Overshoot past the starting corner, the way a hand closes a box.
        let a = corners[0], b = corners[1]
        path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * 0.08, y: a.y + (b.y - a.y) * 0.08 + random.signed() * jitter))
        return path
    }

    static func ellipse(_ r: CGRect, seed: UInt64) -> Path {
        var random = Random(state: seed)
        let start = random.next() * .pi * 2
        let sweep = CGFloat.pi * 2 + 0.3
        let phase = random.next() * .pi * 2
        let steps = 36
        var points: [CGPoint] = []
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let angle = start + sweep * progress
            let factor = 1 + 0.018 * sin(3 * angle + phase) - 0.025 * progress
            points.append(CGPoint(x: r.midX + cos(angle) * r.width / 2 * factor,
                                  y: r.midY + sin(angle) * r.height / 2 * factor))
        }
        return smooth(through: points)
    }

    struct Curve {
        var path: Path
        var start: CGPoint
        var end: CGPoint
        var control: CGPoint

        func midpoint(lift: CGFloat) -> CGPoint {
            let x = 0.25 * start.x + 0.5 * control.x + 0.25 * end.x
            let y = 0.25 * start.y + 0.5 * control.y + 0.25 * end.y
            return CGPoint(x: x, y: y - lift)
        }
    }

    /// A slightly bowed line — straight vector arrows read as a diagram tool.
    static func curve(from a: CGPoint, to b: CGPoint, seed: UInt64) -> Curve {
        var random = Random(state: seed)
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max((dx * dx + dy * dy).squareRoot(), 1)
        let bow = length * 0.07 * (random.next() > 0.5 ? 1 : -1)
        let control = CGPoint(x: (a.x + b.x) / 2 - dy / length * bow,
                              y: (a.y + b.y) / 2 + dx / length * bow)
        var path = Path()
        path.move(to: a)
        path.addQuadCurve(to: b, control: control)
        return Curve(path: path, start: a, end: b, control: control)
    }

    /// Catmull–Rom through every point, so a curve passes where it was told to.
    static func smooth(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

/// Remembers when each board cut started revealing so TimelineView can trim.
@MainActor
private enum SketchRevealClock {
    private static var starts: [Int: Date] = [:]

    static func reset(key: Int) {
        starts[key] = Date()
        if starts.count > 32 {
            starts = starts.filter { abs($0.key - key) < 16 }
        }
    }

    static func progress(for key: Int, at date: Date, duration: TimeInterval) -> Double {
        let start = starts[key] ?? date
        if starts[key] == nil { starts[key] = start }
        return min(1, max(0.001, date.timeIntervalSince(start)) / max(duration, 0.2))
    }
}

private extension BoardScene.Shape {
    var isBody: Bool {
        switch self {
        case .circle, .ellipse, .rect, .icon, .array, .bubble, .path: true
        default: false
        }
    }

    var isLink: Bool {
        switch self {
        case .arrow, .line: true
        default: false
        }
    }

    var isWords: Bool {
        switch self {
        case .text, .label: true
        default: false
        }
    }
}

private extension Color {
    /// One ink weight across the board — Pexo "one hand".
    static var boardInk: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.92, green: 0.93, blue: 0.94, alpha: 1)
                : NSColor(srgbRed: 0.12, green: 0.14, blue: 0.16, alpha: 1)
        })
    }

    /// Single accent on an otherwise monochrome set.
    static var boardInkAccent: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.89, green: 0.70, blue: 0.25, alpha: 1)
                : NSColor(srgbRed: 0.60, green: 0.40, blue: 0.0, alpha: 1)
        })
    }

    static var boardSuccess: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.40, green: 0.80, blue: 0.50, alpha: 1)
                : NSColor(srgbRed: 0.10, green: 0.50, blue: 0.24, alpha: 1)
        })
    }

    static var boardProblem: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.98, green: 0.45, blue: 0.40, alpha: 1)
                : NSColor(srgbRed: 0.78, green: 0.16, blue: 0.14, alpha: 1)
        })
    }
}
