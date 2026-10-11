import ApplicationServices
import AppKit
import Foundation

/// Readable text from the focused app's accessibility tree.
///
/// Complements OCR for browsers and document apps where Vision mangles dense
/// prose. Opt-in: only runs when Accessibility extras are trusted — the same
/// gate as pointer warp. Never clicks, never types; read-only snapshot.
///
/// `nonisolated` so the walk runs off the main actor: it is hundreds of
/// cross-process attribute reads, and on the main actor it held "Reading your
/// screen…" for as long as the frontmost app took to answer them.
nonisolated enum AXPageReader {
    /// Soft cap so a huge DOM cannot inflate the prompt past usefulness.
    static let characterLimit = 6000
    static let maxNodes = 400

    /// Text under the focused application, or nil when AX is off / empty.
    static func snapshot() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let system = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString,
                                            &focusedApp) == .success,
              let focusedApp
        else { return nil }

        let app = focusedApp as! AXUIElement
        var lines: [String] = []
        var seen = Set<String>()
        var nodes = 0

        walk(app, depth: 0, into: &lines, seen: &seen, nodes: &nodes)

        let joined = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        if joined.count <= characterLimit { return joined }
        return String(joined.prefix(characterLimit))
    }

    private static func walk(_ element: AXUIElement,
                             depth: Int,
                             into lines: inout [String],
                             seen: inout Set<String>,
                             nodes: inout Int) {
        guard depth < 12, nodes < maxNodes else { return }
        nodes += 1

        for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                          kAXHelpAttribute] as [CFString] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
                  let string = value as? String
            else { continue }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { continue }
            // Skip single glyphs and pure whitespace chrome.
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            lines.append(trimmed)
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString,
                                            &children) == .success,
              let array = children as? [AXUIElement]
        else { return }

        for child in array.prefix(80) {
            walk(child, depth: depth + 1, into: &lines, seen: &seen, nodes: &nodes)
        }
    }
}
