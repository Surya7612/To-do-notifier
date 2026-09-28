import Foundation

/// A diagram Max draws on the teaching grid — its own surface, never over the
/// user's screen.
///
/// Lesson marks annotate what Vision already found. A board invents geometry
/// for a concept that is not printed there (a molecule, a recursion tree, a
/// data-flow sketch). PLAN Phase 11 keeps those apart on purpose: invented
/// coordinates belong here, not on OCR boxes.
///
/// The model emits a closed ` ```board ` fence with JSON. Invalid or incomplete
/// JSON yields nothing — the spoken answer still stands, same refusal rule as
/// `Lesson.from`.
///
/// Foundation-only and `nonisolated`, same footing as `Lesson`. Wire types for
/// JSON live *inside* this type so `InferIsolatedConformances` cannot pin their
/// `Decodable` conformance to the main actor. Colours resolve in `BoardView`.
nonisolated struct BoardScene: Equatable, Sendable {
    var title: String?
    var frames: [Frame]

    struct Frame: Equatable, Sendable {
        /// 1-based lesson step when teaching. Nil for Explain frames shown in order.
        var step: Int?
        var shapes: [Shape]
    }

    /// Concept colours the model may name. Raw hex is refused so Light/Dark
    /// stay coherent and a typo cannot paint invisible ink.
    enum ColorToken: String, Equatable, Sendable, Codable, CaseIterable {
        case oxygen
        case hydrogen
        case carbon
        case nitrogen
        case accent
        case emphasis
        case muted
        case success
        case problem
        case primary

        /// Fallback when the model invents a token — readable, not alarming.
        static func resolve(_ raw: String?) -> ColorToken {
            guard let raw, let token = ColorToken(rawValue: raw.lowercased()) else {
                return .accent
            }
            return token
        }
    }

    enum Shape: Equatable, Sendable {
        case circle(id: String?, x: Double, y: Double, r: Double, color: ColorToken, label: String?)
        case ellipse(id: String?, x: Double, y: Double, w: Double, h: Double, color: ColorToken, label: String?)
        case rect(id: String?, x: Double, y: Double, w: Double, h: Double, color: ColorToken, label: String?)
        case text(x: Double, y: Double, text: String, color: ColorToken)
        case label(x: Double, y: Double, text: String, color: ColorToken)
        case arrow(from: Endpoint, to: Endpoint, color: ColorToken)
        case line(from: Endpoint, to: Endpoint, color: ColorToken)

        enum Endpoint: Equatable, Sendable {
            case point(x: Double, y: Double)
            case id(String)
        }
    }

    /// Reads a board out of a finished (or mid-stream) answer.
    ///
    /// Only a *closed* `board` fence counts. An open fence mid-stream would
    /// otherwise paint a half-parsed diagram and then jump when the rest arrives.
    static func from(answer: String) -> BoardScene? {
        guard let json = extractBoardJSON(from: answer) else { return nil }
        return decode(json)
    }

    /// Frame to show for a 0-based lesson step. Prefers an exact `step` match;
    /// otherwise the frame at that index when steps are omitted.
    func frameIndex(forLessonStep lessonStep: Int) -> Int {
        let oneBased = lessonStep + 1
        if let match = frames.firstIndex(where: { $0.step == oneBased }) {
            return match
        }
        return min(max(lessonStep, 0), max(frames.count - 1, 0))
    }

    /// Next Explain frame while speech advances (clamped).
    func clampedFrameIndex(_ index: Int) -> Int {
        guard !frames.isEmpty else { return 0 }
        return min(max(index, 0), frames.count - 1)
    }

    /// Contents of the last closed ```board fence, or nil.
    static func extractBoardJSON(from answer: String) -> String? {
        let lines = answer.components(separatedBy: .newlines)
        var blocks: [(lang: String, body: [String])] = []
        var currentLang: String?
        var currentBody: [String]?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if currentBody != nil {
                    blocks.append((currentLang ?? "", currentBody!))
                    currentLang = nil
                    currentBody = nil
                } else {
                    let lang = String(trimmed.dropFirst(3))
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    currentLang = lang
                    currentBody = []
                }
            } else {
                currentBody?.append(line)
            }
        }

        guard let board = blocks.last(where: { $0.lang == "board" || $0.lang.hasPrefix("board") })
        else { return nil }
        let contents = board.body.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return contents.isEmpty ? nil : contents
    }

    static func decode(_ json: String) -> BoardScene? {
        guard let data = json.data(using: .utf8) else { return nil }
        do {
            let raw = try JSONDecoder().decode(RawScene.self, from: data)
            let frames = raw.frames.compactMap(makeFrame(_:))
            guard !frames.isEmpty else { return nil }
            let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return BoardScene(title: title?.isEmpty == true ? nil : title, frames: frames)
        } catch {
            return nil
        }
    }

    private static func makeFrame(_ raw: RawFrame) -> Frame? {
        let shapes = raw.shapes.compactMap(makeShape(_:))
        guard !shapes.isEmpty else { return nil }
        return Frame(step: raw.step, shapes: shapes)
    }

    private static func makeShape(_ raw: RawShape) -> Shape? {
        let color = ColorToken.resolve(raw.color)
        switch raw.type.lowercased() {
        case "circle":
            guard let x = raw.x, let y = raw.y, let r = raw.r, r > 0 else { return nil }
            return .circle(id: raw.id, x: clamp01(x), y: clamp01(y), r: min(r, 0.5),
                           color: color, label: raw.label)
        case "ellipse":
            guard let x = raw.x, let y = raw.y, let w = raw.w, let h = raw.h,
                  w > 0, h > 0 else { return nil }
            return .ellipse(id: raw.id, x: clamp01(x), y: clamp01(y),
                            w: min(w, 1), h: min(h, 1), color: color, label: raw.label)
        case "rect", "rectangle":
            guard let x = raw.x, let y = raw.y, let w = raw.w, let h = raw.h,
                  w > 0, h > 0 else { return nil }
            return .rect(id: raw.id, x: clamp01(x), y: clamp01(y),
                         w: min(w, 1), h: min(h, 1), color: color, label: raw.label)
        case "text":
            guard let x = raw.x, let y = raw.y,
                  let text = raw.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return .text(x: clamp01(x), y: clamp01(y), text: text, color: color)
        case "label":
            guard let x = raw.x, let y = raw.y,
                  let text = (raw.text ?? raw.label)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return .label(x: clamp01(x), y: clamp01(y), text: text, color: color)
        case "arrow":
            guard let from = endpoint(raw, prefix: "from"),
                  let to = endpoint(raw, prefix: "to") else { return nil }
            return .arrow(from: from, to: to, color: color)
        case "line":
            guard let from = endpoint(raw, prefix: "from"),
                  let to = endpoint(raw, prefix: "to") else { return nil }
            return .line(from: from, to: to, color: color)
        default:
            return nil
        }
    }

    private static func endpoint(_ raw: RawShape, prefix: String) -> Shape.Endpoint? {
        if prefix == "from" {
            if let id = raw.from, !id.isEmpty { return .id(id) }
            if let x = raw.fromX, let y = raw.fromY { return .point(x: clamp01(x), y: clamp01(y)) }
        } else {
            if let id = raw.to, !id.isEmpty { return .id(id) }
            if let x = raw.toX, let y = raw.toY { return .point(x: clamp01(x), y: clamp01(y)) }
        }
        return nil
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    // MARK: Wire format (nested so Decodable stays nonisolated)

    private struct RawScene: Decodable, Sendable {
        var title: String?
        var frames: [RawFrame]
    }

    private struct RawFrame: Decodable, Sendable {
        var step: Int?
        var shapes: [RawShape]
    }

    private struct RawShape: Decodable, Sendable {
        var type: String
        var id: String?
        var x: Double?
        var y: Double?
        var r: Double?
        var w: Double?
        var h: Double?
        var text: String?
        var label: String?
        var color: String?
        var from: String?
        var to: String?
        var fromX: Double?
        var fromY: Double?
        var toX: Double?
        var toY: Double?
    }
}
