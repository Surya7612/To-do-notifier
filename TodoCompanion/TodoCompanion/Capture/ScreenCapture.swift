import AppKit
import CoreGraphics
import ScreenCaptureKit

/// One display's worth of pixels and the text found in them.
struct CapturedDisplay {
    let image: CGImage
    /// 1-based, and only ever used for labelling text sent to the model.
    let index: Int
    var recognizedText: String = ""
    /// Where each word sat, kept so an answer can point at what it names.
    var textRegions: [TextRegion] = []
}

/// Everything captured on one summon, plus the context we know about it.
///
/// `primary` is a separate field rather than the first element of an array so
/// the display the user was actually looking at is guaranteed to exist.
struct ScreenObservation {
    var primary: CapturedDisplay
    var others: [CapturedDisplay] = []
    let appName: String?
    let windowTitle: String?

    /// True once the user has narrowed this to a region they chose. The model
    /// is told, so it answers about the selection rather than the whole screen.
    var isCropped = false

    /// The area of the screen, in global AppKit coordinates, that `image`
    /// covers: the focused display normally, the dragged-out region after a
    /// crop. Needed to turn a normalized text box back into a place on screen,
    /// and nil in tests that never involve a real display.
    var primaryScreenFrame: CGRect?

    /// The focused display. This is the one stored with a saved context; a
    /// second monitor's pixels are rarely what the user meant to keep.
    var image: CGImage { primary.image }

    var displays: [CapturedDisplay] { [primary] + others }

    /// Labelled per display when there is more than one, so the model can tell
    /// which text the user is actually looking at.
    var recognizedText: String {
        guard !others.isEmpty else { return primary.recognizedText }
        return displays
            .filter { !$0.recognizedText.isEmpty }
            .map { display in
                let label = display.index == primary.index
                    ? "[Display \(display.index) — focused]"
                    : "[Display \(display.index)]"
                return "\(label)\n\(display.recognizedText)"
            }
            .joined(separator: "\n\n")
    }

    var contextLabel: String {
        switch (appName, windowTitle) {
        case let (app?, title?) where !title.isEmpty: "\(app) — \(title)"
        case let (app?, _): app
        default: "Screen"
        }
    }

    /// Narrows to a region the user dragged out, given in global screen
    /// coordinates on `screen`.
    ///
    /// Other displays are dropped: once someone has pointed at a specific
    /// rectangle, text from a different monitor is noise rather than context.
    func cropped(to selection: CGRect, on screen: NSScreen) -> ScreenObservation? {
        // The area the current image covers, which after an earlier crop is the
        // previous selection rather than the display. Measuring a second
        // selection against the whole screen scaled it by the wrong factor and
        // offset it by the first crop's origin, so re-selecting a region either
        // cropped somewhere else entirely or failed as "too small to read".
        cropped(to: selection, inDisplayFrame: primaryScreenFrame ?? screen.frame)
    }

    /// The coordinate arithmetic, split out from `NSScreen` because that class
    /// cannot be constructed in a test and this conversion is the easiest thing
    /// here to get subtly wrong.
    func cropped(to selection: CGRect, inDisplayFrame frame: CGRect) -> ScreenObservation? {
        guard frame.width > 0, frame.height > 0 else { return nil }

        // The capture is the whole display at backing scale; derive the factor
        // from the image itself rather than trusting a stored scale.
        let scale = CGFloat(primary.image.width) / frame.width

        // AppKit's origin is bottom-left, CoreGraphics images are top-left.
        let pixels = CGRect(
            x: (selection.minX - frame.minX) * scale,
            y: (frame.maxY - selection.maxY) * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).integral

        let bounds = CGRect(x: 0, y: 0, width: primary.image.width, height: primary.image.height)
        let clamped = pixels.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 8, clamped.height >= 8,
              let cut = primary.image.cropping(to: clamped)
        else { return nil }

        var narrowed = self
        narrowed.primary = CapturedDisplay(image: cut, index: primary.index)
        narrowed.others = []
        narrowed.isCropped = true
        // The selection, not the display: text boxes from the re-read of this
        // crop are normalized against the crop, so that is what they map into.
        narrowed.primaryScreenFrame = selection
        return narrowed
    }
}

enum ScreenCaptureError: LocalizedError {
    case noDisplay
    case permissionDenied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            "No display available to capture."
        case .permissionDenied:
            "Screen Recording permission is needed."
        case let .failed(detail):
            "Couldn't read the screen: \(detail)"
        }
    }
}

enum ScreenCapture {
    /// Captures the display under the cursor, omitting this app so the companion
    /// never appears in its own screenshot.
    /// Whether the OS will actually let us capture right now.
    ///
    /// Checking this up front matters because the permission can read as granted
    /// in System Settings while still being denied: an ad-hoc signed build is
    /// authorized by code hash, so every rebuild invalidates the existing grant
    /// and leaves a stale row in the list.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompts once. Does nothing on later calls, so it is safe to retry.
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Captures every attached display, with the one under the cursor as
    /// primary. A second monitor usually holds the documentation, terminal, or
    /// chat the question is really about, so ignoring it loses the context that
    /// makes the answer useful.
    static func captureAllDisplays(frontmostApp: NSRunningApplication?) async throws -> ScreenObservation {
        guard hasPermission else {
            requestPermission()
            throw ScreenCaptureError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // Don't assume permission: report what actually went wrong.
            throw hasPermission
                ? ScreenCaptureError.failed(error.localizedDescription)
                : ScreenCaptureError.permissionDenied
        }

        let focused = displayUnderCursor(in: content) ?? content.displays.first
        guard let focused else { throw ScreenCaptureError.noDisplay }

        let ownBundleID = Bundle.main.bundleIdentifier
        let excluded = content.applications.filter { $0.bundleIdentifier == ownBundleID }

        // Ordered so the focused display is always index 1 in anything the
        // model reads, regardless of how macOS happens to enumerate them.
        let ordered = [focused] + content.displays.filter { $0.displayID != focused.displayID }

        let captured = try await withThrowingTaskGroup(of: (Int, CGImage).self) { group in
            for (offset, display) in ordered.enumerated() {
                let shot = DisplayShot(display: display, excluded: excluded)
                group.addTask {
                    (offset, try await shoot(shot.display, excluding: shot.excluded))
                }
            }
            var byIndex: [Int: CGImage] = [:]
            for try await (offset, image) in group { byIndex[offset] = image }
            return byIndex
        }

        guard let primaryImage = captured[0] else { throw ScreenCaptureError.noDisplay }

        let others = ordered.indices.dropFirst().compactMap { offset in
            captured[offset].map { CapturedDisplay(image: $0, index: offset + 1) }
        }

        var observation = ScreenObservation(
            primary: CapturedDisplay(image: primaryImage, index: 1),
            others: others,
            appName: frontmostApp?.localizedName,
            windowTitle: frontWindowTitle(in: content, for: frontmostApp)
        )
        observation.primaryScreenFrame = nsScreen(for: focused)?.frame
        return observation
    }

    /// Carries ScreenCaptureKit's descriptors into the per-display child tasks.
    ///
    /// Neither `SCDisplay` nor `SCRunningApplication` is `Sendable`, and the
    /// displays are captured concurrently, so the compiler refuses the transfer
    /// and cannot be shown otherwise from here.
    ///
    /// It is sound because the child tasks only ever *read* them: `shoot` takes
    /// the display's dimensions and hands both straight to an `SCContentFilter`.
    /// Nothing in this file mutates a descriptor that `SCShareableContent`
    /// returned, and nothing outside it ever sees one. Boxing them is preferred
    /// to capturing the displays one at a time, which would trade a real
    /// property of the code — every screen grabbed at the same instant — for
    /// the convenience of not having to say this.
    /// `nonisolated` as well as `Sendable`: the module defaults to `MainActor`,
    /// so without it the properties could not be read from the child task that
    /// the box exists to reach.
    private nonisolated struct DisplayShot: @unchecked Sendable {
        let display: SCDisplay
        let excluded: [SCRunningApplication]
    }

    private static func shoot(_ display: SCDisplay,
                              excluding excluded: [SCRunningApplication]) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])

        let scale = backingScale(for: display)
        let config = SCStreamConfiguration()
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func displayUnderCursor(in content: SCShareableContent) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        return content.displays.first { $0.displayID == displayID }
    }

    private static func nsScreen(for display: SCDisplay) -> NSScreen? {
        NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == display.displayID
        }
    }

    private static func backingScale(for display: SCDisplay) -> Double {
        min(2.0, Double(nsScreen(for: display)?.backingScaleFactor ?? 2.0))
    }

    private static func frontWindowTitle(in content: SCShareableContent,
                                         for app: NSRunningApplication?) -> String? {
        guard let pid = app?.processIdentifier else { return nil }
        return content.windows
            .first { $0.owningApplication?.processID == pid && $0.isOnScreen && !($0.title ?? "").isEmpty }?
            .title
    }
}
