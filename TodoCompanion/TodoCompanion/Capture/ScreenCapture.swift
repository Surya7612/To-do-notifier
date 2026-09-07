import AppKit
import CoreGraphics
import ScreenCaptureKit

/// One screenshot plus the surrounding context we know about it.
struct ScreenObservation {
    let image: CGImage
    let appName: String?
    let windowTitle: String?
    var recognizedText: String = ""

    var contextLabel: String {
        switch (appName, windowTitle) {
        case let (app?, title?) where !title.isEmpty: "\(app) — \(title)"
        case let (app?, _): app
        default: "Screen"
        }
    }
}

enum ScreenCaptureError: LocalizedError {
    case noDisplay
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay: "No display available to capture."
        case .permissionDenied:
            "Screen Recording permission is required. Enable it in System Settings → Privacy & Security → Screen Recording."
        }
    }
}

enum ScreenCapture {
    /// Captures the display under the cursor, omitting this app so the companion
    /// never appears in its own screenshot.
    static func captureDisplayUnderCursor(frontmostApp: NSRunningApplication?) async throws -> ScreenObservation {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.permissionDenied
        }

        guard let display = displayUnderCursor(in: content) ?? content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }

        let ownBundleID = Bundle.main.bundleIdentifier
        let excluded = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])

        let scale = backingScale(for: display)
        let config = SCStreamConfiguration()
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        return ScreenObservation(
            image: image,
            appName: frontmostApp?.localizedName,
            windowTitle: frontWindowTitle(in: content, for: frontmostApp)
        )
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

    private static func backingScale(for display: SCDisplay) -> Double {
        let screen = NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == display.displayID
        }
        return min(2.0, Double(screen?.backingScaleFactor ?? 2.0))
    }

    private static func frontWindowTitle(in content: SCShareableContent,
                                         for app: NSRunningApplication?) -> String? {
        guard let pid = app?.processIdentifier else { return nil }
        return content.windows
            .first { $0.owningApplication?.processID == pid && $0.isOnScreen && !($0.title ?? "").isEmpty }?
            .title
    }
}
