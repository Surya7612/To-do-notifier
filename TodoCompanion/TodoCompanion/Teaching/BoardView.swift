import AppKit
import SwiftUI

/// Graph-paper teaching surface Max draws a `BoardScene` onto.
///
/// Opaque paper (not a translucent overlay): the same contrast rule as the
/// panel's code well and lesson captions — text whose brightness comes from
/// the wallpaper is text nobody can read.
struct BoardView: View {
    let scene: BoardScene
    let frameIndex: Int
    var onClose: (() -> Void)?

    private static let boardSize = CGSize(width: 420, height: 420)

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                BoardPaper()
                BoardCanvas(frame: currentFrame, size: Self.boardSize)
            }
            .frame(width: Self.boardSize.width, height: Self.boardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(DS.Spacing.normal)
        }
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
        let index = scene.clampedFrameIndex(frameIndex)
        return scene.frames[index]
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.tight) {
            Text(scene.title ?? "Board")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: DS.Spacing.tight)
            if scene.frames.count > 1 {
                Text("\(scene.clampedFrameIndex(frameIndex) + 1)/\(scene.frames.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close the board")
            }
        }
        .padding(.horizontal, DS.Spacing.normal)
        .padding(.top, DS.Spacing.normal)
        .padding(.bottom, DS.Spacing.tight)
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

/// Draws one frame's shapes in normalized board coordinates.
private struct BoardCanvas: View {
    let frame: BoardScene.Frame
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            let centers = resolveCenters(in: canvasSize)

            for shape in frame.shapes {
                switch shape {
                case let .line(from, to, color):
                    guard let a = point(from, centers: centers, in: canvasSize),
                          let b = point(to, centers: centers, in: canvasSize) else { continue }
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    context.stroke(path, with: .color(color.color),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round))

                case let .arrow(from, to, color):
                    guard let a = point(from, centers: centers, in: canvasSize),
                          let b = point(to, centers: centers, in: canvasSize) else { continue }
                    drawArrow(from: a, to: b, color: color.color, in: &context)

                default:
                    continue
                }
            }

            for shape in frame.shapes {
                switch shape {
                case let .circle(_, x, y, r, color, label):
                    let rect = CGRect(x: x * canvasSize.width - r * canvasSize.width,
                                      y: y * canvasSize.height - r * canvasSize.width,
                                      width: r * canvasSize.width * 2,
                                      height: r * canvasSize.width * 2)
                    let path = Path(ellipseIn: rect)
                    context.fill(path, with: .color(color.color.opacity(0.85)))
                    context.stroke(path, with: .color(color.color), lineWidth: 2)
                    if let label {
                        drawCenteredLabel(label, in: rect, color: .white, context: &context)
                    }

                case let .ellipse(_, x, y, w, h, color, label):
                    let rect = CGRect(x: x * canvasSize.width,
                                      y: y * canvasSize.height,
                                      width: w * canvasSize.width,
                                      height: h * canvasSize.height)
                    let path = Path(ellipseIn: rect)
                    context.fill(path, with: .color(color.color.opacity(0.8)))
                    context.stroke(path, with: .color(color.color), lineWidth: 2)
                    if let label {
                        drawCenteredLabel(label, in: rect, color: .white, context: &context)
                    }

                case let .rect(_, x, y, w, h, color, label):
                    let rect = CGRect(x: x * canvasSize.width,
                                      y: y * canvasSize.height,
                                      width: w * canvasSize.width,
                                      height: h * canvasSize.height)
                    let path = Path(roundedRect: rect, cornerRadius: 8)
                    context.fill(path, with: .color(color.color.opacity(0.8)))
                    context.stroke(path, with: .color(color.color), lineWidth: 2)
                    if let label {
                        drawCenteredLabel(label, in: rect, color: .white, context: &context)
                    }

                default:
                    continue
                }
            }
        }
        .overlay {
            // Text needs SwiftUI layout; Canvas text is awkward for wrapping tips.
            ZStack(alignment: .topLeading) {
                ForEach(Array(textItems.enumerated()), id: \.offset) { _, item in
                    Text(item.text)
                        .font(item.isChip ? .caption.weight(.semibold) : .callout.weight(.medium))
                        .foregroundStyle(item.isChip ? Color.white : item.color.color)
                        .multilineTextAlignment(.center)
                        .lineLimit(item.isChip ? 1 : 3)
                        .padding(.horizontal, item.isChip ? 8 : 10)
                        .padding(.vertical, item.isChip ? 4 : 6)
                        .background {
                            if item.isChip {
                                Capsule().fill(item.color.color)
                            } else {
                                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.92))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                            .strokeBorder(item.color.color.opacity(0.45))
                                    )
                            }
                        }
                        .frame(maxWidth: item.isChip ? 120 : 280)
                        .position(x: item.x * size.width, y: item.y * size.height)
                }
            }
        }
    }

    private struct TextItem {
        let x: Double
        let y: Double
        let text: String
        let color: BoardScene.ColorToken
        let isChip: Bool
    }

    private var textItems: [TextItem] {
        frame.shapes.compactMap { shape in
            switch shape {
            case let .text(x, y, text, color):
                return TextItem(x: x, y: y, text: text, color: color, isChip: false)
            case let .label(x, y, text, color):
                return TextItem(x: x, y: y, text: text, color: color, isChip: true)
            default:
                return nil
            }
        }
    }

    private func resolveCenters(in canvasSize: CGSize) -> [String: CGPoint] {
        var centers: [String: CGPoint] = [:]
        for shape in frame.shapes {
            switch shape {
            case let .circle(id, x, y, _, _, _):
                if let id { centers[id] = CGPoint(x: x * canvasSize.width, y: y * canvasSize.height) }
            case let .ellipse(id, x, y, w, h, _, _):
                if let id {
                    centers[id] = CGPoint(x: (x + w / 2) * canvasSize.width,
                                          y: (y + h / 2) * canvasSize.height)
                }
            case let .rect(id, x, y, w, h, _, _):
                if let id {
                    centers[id] = CGPoint(x: (x + w / 2) * canvasSize.width,
                                          y: (y + h / 2) * canvasSize.height)
                }
            default:
                continue
            }
        }
        return centers
    }

    private func point(_ endpoint: BoardScene.Shape.Endpoint,
                       centers: [String: CGPoint],
                       in canvasSize: CGSize) -> CGPoint? {
        switch endpoint {
        case let .point(x, y):
            return CGPoint(x: x * canvasSize.width, y: y * canvasSize.height)
        case let .id(name):
            return centers[name]
        }
    }

    private func drawArrow(from: CGPoint, to: CGPoint, color: Color, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        let angle = atan2(to.y - from.y, to.x - from.x)
        let head: CGFloat = 10
        var headPath = Path()
        headPath.move(to: to)
        headPath.addLine(to: CGPoint(x: to.x - head * cos(angle - .pi / 6),
                                     y: to.y - head * sin(angle - .pi / 6)))
        headPath.move(to: to)
        headPath.addLine(to: CGPoint(x: to.x - head * cos(angle + .pi / 6),
                                     y: to.y - head * sin(angle + .pi / 6)))
        context.stroke(headPath, with: .color(color),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }

    private func drawCenteredLabel(_ text: String, in rect: CGRect, color: Color,
                                   context: inout GraphicsContext) {
        let resolved = Text(text)
            .font(.headline.weight(.bold))
            .foregroundColor(color)
        context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }
}

extension BoardScene.ColorToken {
    /// SwiftUI colour for drawing on the opaque board.
    var color: Color {
        switch self {
        case .oxygen: Color.boardAdaptive(dark: 0xE06C75, light: 0xCF222E)
        case .hydrogen: Color.boardAdaptive(dark: 0x61AFEF, light: 0x0969DA)
        case .carbon: Color.boardAdaptive(dark: 0xABB2BF, light: 0x424A53)
        case .nitrogen: Color.boardAdaptive(dark: 0xC678DD, light: 0x8250DF)
        case .accent: Color.boardAdaptive(dark: 0xE3B341, light: 0x9A6700)
        case .emphasis: Color.boardAdaptive(dark: 0xE5C07B, light: 0x9A6700)
        case .muted: Color.boardAdaptive(dark: 0x7F848E, light: 0x6E7781)
        case .success: Color.boardAdaptive(dark: 0x98C379, light: 0x1A7F37)
        case .problem: Color.boardAdaptive(dark: 0xE06C75, light: 0xCF222E)
        case .primary: Color.primary
        }
    }
}

private extension Color {
    static func boardAdaptive(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: Double((rgb >> 16) & 0xFF) / 255,
                           green: Double((rgb >> 8) & 0xFF) / 255,
                           blue: Double(rgb & 0xFF) / 255,
                           alpha: 1)
        })
    }
}
