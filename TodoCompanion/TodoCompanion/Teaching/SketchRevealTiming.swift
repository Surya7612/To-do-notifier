import Foundation

/// Baseline pacing for one board frame, independent of narration.
///
/// `SketchTimeline` paces a frame against what Max says over it; this is the
/// floor it never drops below, and what an unnarrated frame uses. Pure and
/// `nonisolated`.
nonisolated enum SketchRevealTiming: Sendable {
    /// Seconds to fully draw a frame with this many subjects / links.
    static func durationSeconds(subjectCount: Int, linkCount: Int = 0) -> TimeInterval {
        let subjects = max(subjectCount, 1)
        let links = max(linkCount, 0)
        return 0.25 + Double(subjects) * 0.32 + Double(links) * 0.10 + 0.35
    }

    /// How long teaching waits before speaking. Short on purpose: the pen is
    /// paced across the sentence, so the voice should start while it draws.
    static let voiceLeadSeconds: TimeInterval = 0.3

    static func durationSeconds(for frame: BoardScene.Frame) -> TimeInterval {
        let subjects = frame.shapes.filter {
            switch $0 {
            case .circle, .ellipse, .rect, .icon, .array, .path: return true
            default: return false
            }
        }.count
        let links = frame.shapes.filter {
            switch $0 {
            case .arrow, .line, .mark: return true
            default: return false
            }
        }.count
        return durationSeconds(subjectCount: subjects, linkCount: links)
    }
}
