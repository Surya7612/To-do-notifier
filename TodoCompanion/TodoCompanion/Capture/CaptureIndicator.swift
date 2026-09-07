import AppKit
import Observation
import SwiftUI

/// Live values the ring reads every frame.
///
/// Separate from the window so SwiftUI can observe it without the indicator
/// having to rebuild its hosting view on every update.
@Observable
final class IndicatorState {
    var mode: CaptureIndicator.Mode = .capturing
    var level: CGFloat = 0
}

/// A ring that pulses at the cursor while the screen is being read or the
/// microphone is open.
///
/// macOS does not show its recording indicator for one-shot ScreenCaptureKit
/// grabs, so without this the capture is completely invisible — which is exactly
/// the wrong property for a feature that reads your screen. The window belongs
/// to this app, so it is excluded from the screenshot along with the panel.
@MainActor
final class CaptureIndicator {
    /// What the ring is telling the user is happening.
    enum Mode {
        case capturing
        case listening

        var tint: Color {
            switch self {
            case .capturing: DS.Status.saved
            case .listening: DS.Status.listening
            }
        }

        var glyph: String {
            switch self {
            case .capturing: "viewfinder"
            case .listening: "waveform"
            }
        }

        /// Listening lasts as long as the user holds the floor, so it gets no
        /// minimum: it ends exactly when they stop talking.
        var minimumVisible: TimeInterval {
            switch self {
            case .capturing: 0.45
            case .listening: 0
            }
        }
    }

    private static let diameter = DS.Size.indicator

    private let state = IndicatorState()

    private var window: NSWindow?
    private var shownAt: Date?
    private var pendingHide: Task<Void, Never>?
    private var tracking: Task<Void, Never>?

    /// `level` is polled rather than pushed: the audio tap runs on a render
    /// thread many times a second, and hopping to the main actor per buffer to
    /// drive an animation is far more traffic than a 60Hz read needs.
    func show(_ mode: Mode = .capturing,
              at point: NSPoint? = nil,
              level: (@MainActor () -> CGFloat)? = nil) {
        pendingHide?.cancel()
        pendingHide = nil
        state.mode = mode
        state.level = 0

        let window = existingWindow()
        center(window, on: point ?? NSEvent.mouseLocation)
        window.orderFrontRegardless()
        shownAt = Date()

        // A ring pinned to where the cursor *was* reads as a stray artifact.
        // Following it keeps the feedback attached to the user's attention,
        // which matters most while listening, since that can run for a while.
        startTracking(window, followCursor: point == nil, level: level)
    }

    func hide() {
        let floor = state.mode.minimumVisible
        let elapsed = shownAt.map { Date().timeIntervalSince($0) } ?? floor
        let remaining = floor - elapsed

        guard remaining > 0 else {
            dismiss()
            return
        }

        pendingHide = Task {
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func startTracking(_ window: NSWindow,
                               followCursor: Bool,
                               level: (@MainActor () -> CGFloat)?) {
        tracking?.cancel()
        guard followCursor || level != nil else { return }

        tracking = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if followCursor { self.center(window, on: NSEvent.mouseLocation) }
                if let level {
                    // Ease toward the new reading so the ring breathes instead
                    // of flickering on every buffer.
                    let target = level()
                    self.state.level += (target - self.state.level) * (target > self.state.level ? 0.5 : 0.12)
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func center(_ window: NSWindow, on point: NSPoint) {
        window.setFrameOrigin(
            NSPoint(x: point.x - Self.diameter / 2, y: point.y - Self.diameter / 2)
        )
    }

    private func dismiss() {
        tracking?.cancel()
        tracking = nil
        window?.orderOut(nil)
        shownAt = nil
        pendingHide = nil
    }

    private func existingWindow() -> NSWindow {
        if let window { return window }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CaptureRingView(state: state))
        window = panel
        return panel
    }
}

struct CaptureRingView: View {
    let state: IndicatorState

    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(state.mode.tint.opacity(0.85), lineWidth: 2.5)
                .scaleEffect(pulsing ? 0.95 : 0.35)
                .opacity(pulsing ? 0 : 0.95)

            Circle()
                .strokeBorder(state.mode.tint.opacity(0.55), lineWidth: 2)
                .scaleEffect(pulsing ? 0.6 : 0.2)
                .opacity(pulsing ? 0.15 : 0.8)

            if state.mode == .listening {
                voiceRing
            }

            Image(systemName: state.mode.glyph)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(state.mode.tint)
                .opacity(0.9)
        }
        .animation(.easeOut(duration: 0.85).repeatForever(autoreverses: false), value: pulsing)
        .onAppear { pulsing = true }
        .onDisappear { pulsing = false }
    }

    /// Tracks the microphone rather than the clock, so silence looks like
    /// silence. A dead input device is visibly dead instead of merely quiet.
    private var voiceRing: some View {
        Circle()
            .strokeBorder(state.mode.tint.opacity(0.35 + state.level * 0.5), lineWidth: 3)
            .scaleEffect(0.34 + state.level * 0.34)
            .animation(.linear(duration: 0.05), value: state.level)
    }
}
