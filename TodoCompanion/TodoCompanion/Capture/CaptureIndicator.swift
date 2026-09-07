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
    private static let diameter: CGFloat = 110
    /// Capture plus OCR can finish in under 100ms; without a floor the ring
    /// would flicker too briefly to register as feedback.
    private static let minimumVisible: TimeInterval = 0.45

    private var window: NSWindow?
    private var shownAt: Date?
    private var pendingHide: Task<Void, Never>?

    func show(at point: NSPoint? = nil) {
        pendingHide?.cancel()
        pendingHide = nil

        let center = point ?? NSEvent.mouseLocation
        let window = existingWindow()
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
        let elapsed = shownAt.map { Date().timeIntervalSince($0) } ?? Self.minimumVisible
        let remaining = Self.minimumVisible - elapsed

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
        panel.contentView = NSHostingView(rootView: CaptureRingView())
        window = panel
        return panel
    }
}

private struct CaptureRingView: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.tint.opacity(0.85), lineWidth: 2.5)
                .scaleEffect(pulsing ? 0.95 : 0.35)
                .opacity(pulsing ? 0 : 0.95)

            Circle()
                .strokeBorder(.tint.opacity(0.55), lineWidth: 2)
                .scaleEffect(pulsing ? 0.6 : 0.2)
                .opacity(pulsing ? 0.15 : 0.8)

            Image(systemName: "viewfinder")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tint)
                .opacity(0.9)
        }
        .animation(.easeOut(duration: 0.85).repeatForever(autoreverses: false), value: pulsing)
        .onAppear { pulsing = true }
        .onDisappear { pulsing = false }
    }
}
