import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// Finds a named control in the frontmost app's accessibility tree.
///
/// Opt-in and secondary to OCR. Max is shown a screenshot, so the words it
/// names are usually ones Vision already has — and AX is thin or absent in
/// exactly the apps pointing is most useful for. When AX *does* know the
/// control, though, it can move or click the pointer, which OCR boxes cannot.
///
/// Motion and clicks run only from a button press. Follow-along and lessons
/// stay on OCR marks and never call into this.
@MainActor
enum AXControlLocator {
    struct Match: Equatable, Sendable {
        let frame: CGRect
        let label: String
        var center: CGPoint {
            CGPoint(x: frame.midX, y: frame.midY)
        }
    }

    /// How a candidate string relates to the target label. Pure; tested.
    enum Rank: Int, Comparable, Sendable {
        case none = 0
        case contains = 1
        case exact = 2

        static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Scores one AX attribute string against the label the answer named.
    nonisolated static func rank(candidate: String, against target: String) -> Rank {
        let needle = normalized(target)
        let hay = normalized(candidate)
        guard !needle.isEmpty, !hay.isEmpty else { return .none }
        if hay == needle { return .exact }
        if hay.split(separator: " ").contains(where: { $0 == Substring(needle) }) {
            return .exact
        }
        if hay.contains(needle), needle.count >= 3 {
            return .contains
        }
        return .none
    }

    /// Best rank among the usual AX label attributes for one element.
    nonisolated static func rank(attributes: [String], against target: String) -> Rank {
        attributes.map { rank(candidate: $0, against: target) }.max() ?? .none
    }

    /// Looks up `label` in the frontmost app. Returns nil when Accessibility is
    /// off, the app exposes no tree, or nothing matches.
    static func locate(label: String) -> Match? {
        guard TrustAccessibility.isTrusted else { return nil }
        let needle = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }

        let system = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString,
                                            &focusedApp) == .success,
              let focusedApp
        else { return nil }

        let app = focusedApp as! AXUIElement
        var best: (rank: Rank, frame: CGRect, label: String)?
        walk(app, depth: 0, against: needle) { rank, frame, matched in
            guard rank > (best?.rank ?? .none) else { return }
            best = (rank, frame, matched)
        }
        guard let best else { return nil }
        return Match(frame: best.frame, label: best.label)
    }

    /// Moves the system pointer to `point` in Cocoa screen coordinates.
    static func movePointer(to point: CGPoint) {
        let flipped = cgPoint(fromCocoa: point)
        CGWarpMouseCursorPosition(flipped)
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    /// Left-clicks at `point` in Cocoa screen coordinates.
    static func click(at point: CGPoint) {
        let flipped = cgPoint(fromCocoa: point)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: flipped, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                         mouseCursorPosition: flipped, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Tree walk

    private static let maxDepth = 12

    private static func walk(_ element: AXUIElement,
                             depth: Int,
                             against target: String,
                             visit: (Rank, CGRect, String) -> Void) {
        guard depth <= maxDepth else { return }

        let attrs = labelAttributes(of: element)
        let rank = rank(attributes: attrs, against: target)
        if rank != .none, let frame = frame(of: element) {
            let matched = attrs.first { self.rank(candidate: $0, against: target) == rank } ?? target
            visit(rank, frame, matched)
            // Exact match is good enough; keep walking siblings but skip children
            // of this node to limit work on large trees.
            if rank == .exact { return }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString,
                                            &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return }

        for child in children {
            walk(child, depth: depth + 1, against: target, visit: visit)
        }
    }

    private static func labelAttributes(of element: AXUIElement) -> [String] {
        let keys: [CFString] = [
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXValueAttribute as CFString,
            kAXIdentifierAttribute as CFString,
        ]
        var values: [String] = []
        for key in keys {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key, &ref) == .success,
                  let ref
            else { continue }
            if let string = ref as? String, !string.isEmpty {
                values.append(string)
            } else if let number = ref as? NSNumber {
                values.append(number.stringValue)
            }
        }
        return values
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString,
                                            &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString,
                                            &sizeRef) == .success,
              let positionRef, let sizeRef
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }

        // AX reports top-left origin in screen space; Cocoa uses bottom-left.
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let cocoaY = screenHeight - position.y - size.height
        return CGRect(x: position.x, y: cocoaY, width: size.width, height: size.height)
    }

    private static func cgPoint(fromCocoa point: CGPoint) -> CGPoint {
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: point.x, y: screenHeight - point.y)
    }

    nonisolated private static func normalized(_ string: String) -> String {
        string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
