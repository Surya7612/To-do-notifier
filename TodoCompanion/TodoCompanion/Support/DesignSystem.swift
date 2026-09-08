import SwiftUI

/// Shared visual constants.
///
/// The panel, the library, and the cursor ring are three separately-authored
/// surfaces that have to look like one app. Naming the values is what keeps a
/// corner radius from drifting to 17 in one of them.
enum DS {
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

    /// One colour per meaning, so status is legible without reading the label.
    enum Status {
        static let ready = Color.green
        static let busy = Color.orange
        static let saved = Color.blue
        static let listening = Color.pink
        static let problem = Color.red
    }
}
