import AppKit
import SwiftUI

/// A ring that pulses at the cursor while the screen is being read.
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
            case .capturing: .blue
            case .listening: .pink
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

    private static let diameter: CGFloat = 110

    private var window: NSWindow?
    private var shownAt: Date?
    private var mode: Mode = .capturing
    private var pendingHide: Task<Void, Never>?

    func show(_ mode: Mode = .capturing, at point: NSPoint? = nil) {
        pendingHide?.cancel()
        pendingHide = nil
        self.mode = mode

        let center = point ?? NSEvent.mouseLocation
        let window = existingWindow()
        (window.contentView as? NSHostingView<CaptureRingView>)?.rootView = CaptureRingView(mode: mode)
        window.setFrame(
            NSRect(x: center.x - Self.diameter / 2,
                   y: center.y - Self.diameter / 2,
                   width: Self.diameter,
                   height: Self.diameter),
            display: false
        )
        window.orderFrontRegardless()
        shownAt = Date()
    }

    func hide() {
        let floor = mode.minimumVisible
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

    private func dismiss() {
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
        panel.contentView = NSHostingView(rootView: CaptureRingView(mode: mode))
        window = panel
        return panel
    }
}

struct CaptureRingView: View {
    let mode: CaptureIndicator.Mode

    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(mode.tint.opacity(0.85), lineWidth: 2.5)
                .scaleEffect(pulsing ? 0.95 : 0.35)
                .opacity(pulsing ? 0 : 0.95)

            Circle()
                .strokeBorder(mode.tint.opacity(0.55), lineWidth: 2)
                .scaleEffect(pulsing ? 0.6 : 0.2)
                .opacity(pulsing ? 0.15 : 0.8)

            Image(systemName: mode.glyph)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(mode.tint)
                .opacity(0.9)
        }
        .animation(.easeOut(duration: 0.85).repeatForever(autoreverses: false), value: pulsing)
        .onAppear { pulsing = true }
        .onDisappear { pulsing = false }
    }
}
