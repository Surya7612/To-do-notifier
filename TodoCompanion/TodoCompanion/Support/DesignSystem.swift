import AppKit
import SwiftUI

/// Shared visual constants.
///
/// The panel, the library, and the cursor ring are three separately-authored
/// surfaces that have to look like one app. Naming the values is what keeps a
/// corner radius from drifting to 17 in one of them.
///
/// Explicitly `nonisolated` because the project defaults to main-actor
/// isolation and the pure types that lay out an answer — `AnswerContent`,
/// `CodeHighlighter` — read these colours while building an `AttributedString`
/// off the main actor. They are constants of a `Sendable` type, so there is
/// nothing for the isolation to protect.
nonisolated enum DS {
    enum Spacing {
        static let hair: CGFloat = 5
        static let tight: CGFloat = 8
        static let snug: CGFloat = 9
        static let card: CGFloat = 10
        static let normal: CGFloat = 12
        static let roomy: CGFloat = 16
    }

    enum Radius {
        static let panel: CGFloat = 18
        static let card: CGFloat = 10
        static let control: CGFloat = 8
        static let chip: CGFloat = 7
    }

    /// Fill and stroke strengths, kept together so "slightly visible" means the
    /// same thing everywhere.
    enum Alpha {
        static let hairline: Double = 0.12
        static let divider: Double = 0.35
        static let chipFill: Double = 0.35
        static let noticeFill: Double = 0.4
        static let fieldFill: Double = 0.5
        /// Recessed background for monospaced content such as a diff.
        static let well: Double = 0.18
        /// Tint behind an added or removed diff line, low enough that the text
        /// stays the thing carrying the meaning.
        static let diffRow: Double = 0.16
    }

    enum Size {
        /// Wide enough for the region controls and both presets to sit in one
        /// row at their natural size.
        static let panelWidth: CGFloat = 468
        /// Past this the answer scrolls rather than growing the window forever.
        static let maxAnswerHeight: CGFloat = 320
        /// A diff sits inside the answer area, so it gets a smaller share of it.
        static let maxDiffHeight: CGFloat = 200
        static let indicator: CGFloat = 110
    }

    /// The code block, and the colours of the tokens in it.
    ///
    /// The well is **opaque**, unlike everything else in the panel. That is the
    /// one thing here that is not a taste decision: the panel is translucent, so
    /// a tinted overlay takes its brightness from whatever application happens
    /// to be behind it, and the same block came out as a dark well over an
    /// editor and a pale grey slab over a browser. Code is the one thing in the
    /// panel that has to stay readable, and it cannot if its background is
    /// decided by the wallpaper.
    ///
    /// The tokens are One Dark and One Light, stated per appearance rather than
    /// taken from the system accent palette. `Color.pink` and friends are tuned
    /// to be *noticed* — they are status colours — and a screen of them is
    /// tiring to read. These are tuned to be read for minutes at a time.
    enum Code {
        static let well = Color(nsColor: .textBackgroundColor)
        static let border = Color.primary.opacity(0.09)

        static let keyword = Color.adaptive(dark: 0xC678DD, light: 0xA626A4)
        static let string = Color.adaptive(dark: 0x98C379, light: 0x50A14F)
        static let number = Color.adaptive(dark: 0xD19A66, light: 0x986801)
        static let type = Color.adaptive(dark: 0x61AFEF, light: 0x4078F2)
        static let comment = Color.adaptive(dark: 0x7F848E, light: 0xA0A1A7)
        static let punctuation = Color.adaptive(dark: 0xABB2BF, light: 0x6A737D)
    }

    /// One colour per meaning, so status is legible without reading the label.
    enum Status {
        static let ready = Color.green
        static let busy = Color.orange

        /// Also the colour of the box drawn on screen and of the labels Max
        /// quoted, which is the reason it is stated per appearance rather than
        /// taken as `Color.blue`. `systemBlue` is picked to sit on an opaque
        /// control background; as small text on a translucent panel over a
        /// dark window it is closer to navy than to blue and reads as
        /// disabled. These stay legible on the panel while remaining
        /// unmistakable as a 2.5pt stroke over someone else's window.
        static let saved = Color.adaptive(dark: 0x74B4F0, light: 0x2E6FDD)

        static let listening = Color.pink
        static let problem = Color.red
    }
}

private extension Color {
    /// A colour stated once per appearance and resolved by AppKit when it is
    /// drawn, so it is still right after the user switches to Light Mode with
    /// the panel already open.
    nonisolated static func adaptive(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    /// Written as `0xRRGGBB` because these came from a published palette in
    /// that form, and transcribing them as three decimals invites a typo that
    /// nothing would catch.
    nonisolated convenience init(rgb: Int) {
        self.init(srgbRed: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
