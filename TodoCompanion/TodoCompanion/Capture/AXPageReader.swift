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
    /// Each AX read otherwise waits about six seconds on an app that is not
    /// answering, and the walk makes hundreds of them, all before "Reading
    /// your screen…" may clear — so a beachballing frontmost app held the
    /// panel there indefinitely. Cancelling the task does not interrupt it.
    static let perCallTimeout: Float = 0.25
    static let walkBudget: TimeInterval = 1.5

    /// Text under the app the capture is about, or nil when AX is off / empty.
    ///
    /// Never this process: an AX query against our own pid is not a message to
    /// another app but a direct call into our own SwiftUI accessibility tree, on
    /// whatever thread asked — and from this background walk that trips the
    /// main-actor assertion and kills the app. The system-wide focused app is
    /// Max whenever the library or Settings window has focus, so the target is
    /// the captured app's pid rather than whatever AX calls focused.
    static func snapshot(processIdentifier: pid_t?) -> String? {
        guard AXIsProcessTrusted(),
              let processIdentifier,
              processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }

        let app = AXUIElementCreateApplication(processIdentifier)
        var lines: [String] = []
        var seen = Set<String>()
        var nodes = 0
        let deadline = Date().addingTimeInterval(walkBudget)

        walk(app, depth: 0, deadline: deadline, into: &lines, seen: &seen, nodes: &nodes)

        let joined = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        if joined.count <= characterLimit { return joined }
        return String(joined.prefix(characterLimit))
    }

    private static func walk(_ element: AXUIElement,
                             depth: Int,
                             deadline: Date,
                             into lines: inout [String],
                             seen: inout Set<String>,
                             nodes: inout Int) {
        guard depth < 12, nodes < maxNodes, Date() < deadline else { return }
        nodes += 1
        AXUIElementSetMessagingTimeout(element, perCallTimeout)

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
            walk(child, depth: depth + 1, deadline: deadline, into: &lines, seen: &seen, nodes: &nodes)
        }
    }
}
