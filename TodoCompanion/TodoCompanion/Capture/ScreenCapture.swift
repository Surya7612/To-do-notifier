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

    static func captureDisplayUnderCursor(frontmostApp: NSRunningApplication?) async throws -> ScreenObservation {
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
