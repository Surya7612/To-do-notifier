import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// A CGEvent tap that watches for Tab+Q.
///
/// Installed only when Accessibility extras are opted in *and* trusted. Carbon
/// hotkeys stay registered either way — this is an addition, not a replacement.
@MainActor
final class EventTapHotkey {
    static let shared = EventTapHotkey()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = TabChordDetector()
    private var action: (() -> Void)?

    private init() {
        // The C callback cannot capture `self` or touch a MainActor static, so
        // it reaches this instance through an unchecked global set here.
        eventTapInstance = self
    }

    /// Installs or tears down the tap to match the current extras state.
    func refresh(action: (() -> Void)? = nil) {
        if let action { self.action = action }

        guard TrustAccessibility.extrasAreActive, self.action != nil else {
            tearDown()
            return
        }
        guard tap == nil else { return }
        install()
    }

    func tearDown() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        tap = nil
        source = nil
        detector = TabChordDetector()
    }

    private func install() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapHotkeyCallback,
            userInfo: nil
        ) else {
            NSLog("[EventTapHotkey] CGEvent tap refused — Accessibility grant may be missing")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    fileprivate func reenableTapIfNeeded() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func noteKey(type: CGEventType, code: Int64, isRepeat: Bool) -> Bool {
        switch type {
        case .keyDown:
            if detector.keyDown(code: code, isRepeat: isRepeat) {
                let action = self.action
                DispatchQueue.main.async { action?() }
                return true // swallow
            }
        case .keyUp:
            detector.keyUp(code: code)
        default:
            break
        }
        return false
    }
}

/// Reachable from the C callback without crossing a MainActor static.
private nonisolated(unsafe) weak var eventTapInstance: EventTapHotkey?

/// Top-level and `nonisolated` so it can be formed into a C function pointer
/// under Swift 6's default MainActor isolation.
private nonisolated func eventTapHotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                eventTapInstance?.reenableTapIfNeeded()
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passUnretained(event)
    }

    let code = event.getIntegerValueField(.keyboardEventKeycode)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

    var swallow = false
    let apply: () -> Void = {
        MainActor.assumeIsolated {
            swallow = eventTapInstance?.noteKey(type: type, code: code, isRepeat: isRepeat) ?? false
        }
    }

    if Thread.isMainThread {
        apply()
    } else {
        DispatchQueue.main.sync(execute: apply)
    }

    return swallow ? nil : Unmanaged.passUnretained(event)
}
