import AppKit
import SwiftData
import SwiftUI

@MainActor
final class CompanionPanelController {
    /// Only the starting height. The panel resizes to whatever the content
    /// actually needs once SwiftUI has laid it out.
    private static let initialSize = NSSize(width: DS.Size.panelWidth, height: 180)

    let viewModel: CompanionViewModel
    private var panel: CompanionPanel?
    private weak var previousApp: NSRunningApplication?

    private let indicator = CaptureIndicator()
    private let highlight = ScreenHighlight()
    private let lessonMarks = LessonOverlay()
    private var outsideClickMonitor: Any?

    init(modelContext: ModelContext) {
        self.viewModel = CompanionViewModel(modelContext: modelContext)
        viewModel.onCaptureBegan = { [weak self] in self?.indicator.show(.capturing) }
        viewModel.onCaptureEnded = { [weak self] in self?.indicator.hide() }
        viewModel.onListeningBegan = { [weak self] in
            self?.indicator.show(.listening, level: { [weak self] in self?.viewModel.currentInputLevel ?? 0 })
        }
        viewModel.onListeningEnded = { [weak self] in self?.indicator.hide() }
        viewModel.onHighlight = { [weak self] rect, untilHidden in
            self?.highlight.show(rect, untilHidden: untilHidden)
        }
        viewModel.onHighlightEnded = { [weak self] in self?.highlight.hide() }
        viewModel.onLessonMarks = { [weak self] current, covered, number, screen in
            self?.lessonMarks.show(current: current, covered: covered, number: number, on: screen)
        }
        viewModel.onLessonEnded = { [weak self] in self?.lessonMarks.hide() }
        viewModel.onPinnedChanged = { [weak self] isPinned in
            guard let self else { return }
            isPinned ? self.stopWatchingForOutsideClick() : self.watchForOutsideClick()
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : summon()
    }

    /// Reads the frontmost app before activating ourselves, otherwise the
    /// captured context would just say "TodoCompanion".
    func summon() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }

        let panel = existingPanel()
        panel.setFrameTopLeftPoint(topLeftNearCursor(for: panel.frame.size))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        watchForOutsideClick()

        // Decides whether the previous conversation is still live before the
        // capture that will be asked about in its terms.
        viewModel.prepareForSummon()
        viewModel.captureScreen(frontmostApp: frontmost)
    }

    /// Brings the panel up with the microphone already open.
    ///
    /// The shortcut exists because the two-step version — summon, then find and
    /// press the microphone — is enough friction that a spoken question tends
    /// to become a typed one, and the whole point of asking about the screen in
    /// front of you is not to look away from it.
    ///
    /// Pressing it again stops, so one key both starts and ends the sentence.
    func summonAndListen() {
        if !viewModel.isListening, !isVisible { summon() }
        NSApp.activate(ignoringOtherApps: true)

        // Started without waiting for the capture to finish, which costs the
        // recognizer the on-screen vocabulary it would otherwise be given. That
        // is the right trade: the user pressed a key in order to talk, and a
        // microphone that opens a second later has missed the first few words.
        viewModel.toggleDictation()
    }

    /// Dismisses when the user clicks away, which is what every other floating
    /// panel on the system does. Only mouse events are observed: a global
    /// *keyboard* monitor would demand Accessibility permission, and avoiding
    /// that is why the hotkey uses Carbon in the first place.
    private func watchForOutsideClick() {
        // Pinning is exactly the suppression of this monitor. It is what makes
        // the panel usable *while* working rather than between bouts of work —
        // reading a lesson step, doing it, and looking back at the panel, all
        // without the act of reaching the editor taking the panel down.
        guard !viewModel.isPinned, outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                // Dismissing mid-sentence would end the recording and, worse,
                // take any failure message down with it. macOS puts its own
                // microphone and speech prompts up as separate windows, so
                // clicking Allow counts as a click outside this app.
                guard !self.viewModel.isListening else { return }

                self.hide()
            }
        }
    }

    /// Steps the panel aside for region selection without tearing down its
    /// state, and suspends the outside-click monitor that would otherwise treat
    /// the drag as a dismissal.
    private func setPanelHidden(_ hidden: Bool) {
        guard let panel else { return }
        if hidden {
            stopWatchingForOutsideClick()
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            watchForOutsideClick()
        }
    }

    private func stopWatchingForOutsideClick() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// Hands focus back to whatever the user was working in, so the companion
    /// does not leave them staring at an empty desktop.
    func hide() {
        stopWatchingForOutsideClick()
        panel?.orderOut(nil)
        // Not `reset()`: the conversation outlives the panel, because reaching
        // the app being discussed means clicking outside this one.
        viewModel.endSession()
        previousApp?.activate()
        previousApp = nil
    }

    private func existingPanel() -> CompanionPanel {
        if let panel { return panel }

        let panel = CompanionPanel(contentRect: NSRect(origin: .zero, size: Self.initialSize))
        panel.onDismiss = { [weak self] in self?.hide() }

        let hosting = NSHostingController(
            rootView: CompanionView(
                viewModel: viewModel,
                onClose: { [weak self] in self?.hide() },
                onRetry: { [weak self] in
                    self?.viewModel.retryCapture(frontmostApp: self?.previousApp)
                },
                onSelectRegion: { [weak self] in
                    self?.viewModel.selectRegion { hidden in
                        // Clicking into the selection overlay is a click outside
                        // the panel, so the dismiss monitor has to stand down.
                        self?.setPanelHidden(hidden)
                    }
                },
                onClearRegion: { [weak self] in
                    self?.viewModel.clearRegion(frontmostApp: self?.previousApp)
                },
                onLookAgain: { [weak self] in
                    self?.viewModel.lookAgain(frontmostApp: self?.previousApp)
                }
            )
        )
        // Lets the answer drive the window height rather than a fixed guess.
        //
        // `.standardBounds` and not `.preferredContentSize`, which crashed the
        // app. The two differ in *when* the window is told how big to be:
        // `.preferredContentSize` has the hosting view set the controller's
        // ideal size during layout, so SwiftUI resizes the window from inside
        // the window's own layout pass — `windowDidLayout` → `_setFrameCommon`
        // → `displayIfNeeded` → layout again. Auto Layout accumulates the
        // pending constraint work across that re-entry until flushing it
        // overflows the main thread's stack, which surfaces as a segfault in
        // CoreAutoLayout with nothing of ours on the stack.
        //
        // `.standardBounds` publishes minimum, ideal and maximum size as
        // constraints instead, so the window is sized by the solver in the
        // ordinary way rather than by a frame change made mid-pass.
        hosting.sizingOptions = .standardBounds
        panel.contentViewController = hosting

        self.panel = panel
        return panel
    }

    /// Returns the top-left corner, because that is the edge the panel keeps
    /// fixed as it grows downward with the answer.
    private func topLeftNearCursor(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let gap: CGFloat = 18
        var x = mouse.x + gap
        if x + size.width > bounds.maxX { x = mouse.x - size.width - gap }
        x = min(max(x, bounds.minX + 8), bounds.maxX - size.width - 8)

        // Hang below the cursor, but flip above it near the bottom of the screen
        // so a tall answer still has somewhere to grow.
        var top = mouse.y - gap
        if top - size.height < bounds.minY { top = mouse.y + gap + size.height }
        top = min(max(top, bounds.minY + size.height + 8), bounds.maxY - 8)

        return NSPoint(x: x, y: top)
    }
}
