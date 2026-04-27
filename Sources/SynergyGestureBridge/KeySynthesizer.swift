import CoreGraphics
import Foundation

/// Carbon virtual key codes used by the bridge.
enum ArrowKey {
    static let left: CGKeyCode = 123
    static let right: CGKeyCode = 124
    static let down: CGKeyCode = 125
    static let up: CGKeyCode = 126
}

/// Synthesizes and posts modifier-plus-arrow keystrokes into the HID event stream.
///
/// Posting is **deferred** to the next main run-loop turn so we are not calling
/// `CGEvent.post` synchronously from inside a `CGEventTap` callback.
///
/// **`SGB_MODIFIER_DELAY_MS`** (default ~12 ms) waits after physical control-down before
/// arrow keys so Synergy and the client OS see a stable modifier (avoids “keys arrive
/// but Spaces / fullscreen does not switch”, especially when a text field would otherwise
/// eat bare arrows).
enum KeySynthesizer {
    /// Left control (`kVK_Control` / 0x3B) for explicit modifier sequences.
    private static let leftControlVK: CGKeyCode = 59

    private static var lastPostedKey: CGKeyCode = 0
    private static var lastPostedAt: CFAbsoluteTime = 0

    private static func truthy(_ raw: String?) -> Bool {
        guard let raw else { return false }
        switch raw.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    /// Milliseconds to wait after control-down before arrow keys (0–500). Default 12.
    private static func modifierHoldDelaySeconds() -> TimeInterval {
        let raw = ProcessInfo.processInfo.environment["SGB_MODIFIER_DELAY_MS"] ?? ""
        if let ms = Double(raw), ms >= 0, ms < 500 {
            return ms / 1000.0
        }
        return 0.012
    }

    /// Called from the event tap. Actual `CGEvent.post` runs asynchronously on the main queue.
    static func postControlArrow(_ key: CGKeyCode) {
        let now = CFAbsoluteTimeGetCurrent()
        if key == lastPostedKey, now - lastPostedAt < 0.06 {
            Logger.debug("skipped duplicate ctrl+arrow keyCode=\(key) (≤60ms)")
            return
        }
        lastPostedKey = key
        lastPostedAt = now

        DispatchQueue.main.async {
            postControlArrowNow(key)
        }
    }

    private static func postKeyboard(
        _ source: CGEventSource?,
        tap: CGEventTapLocation,
        virtualKey: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags
    ) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else {
            return
        }
        event.flags = flags
        event.post(tap: tap)
    }

    private static func postControlArrowNow(_ key: CGKeyCode) {
        let env = ProcessInfo.processInfo.environment
        let tapLoc = env["SGB_TAP_LOCATION"]?.lowercased() ?? ""

        let useHID: Bool
        if env["SGB_POST_SESSION"] == "1" {
            useHID = false
        } else if env["SGB_POST_HID"] == "1" {
            useHID = true
        } else {
            useHID = tapLoc == "hid"
        }

        let sourceID: CGEventSourceStateID = useHID ? .hidSystemState : .combinedSessionState
        let tap: CGEventTapLocation = useHID ? .cghidEventTap : .cgSessionEventTap

        let source = CGEventSource(stateID: sourceID)
        let explicit: Bool
        switch env["SGB_EXPLICIT_MODIFIERS"]?.lowercased() {
        case "0", "false", "no", "off":
            explicit = false
        case "1", "true", "yes", "on":
            explicit = true
        default:
            explicit = useHID
        }

        if explicit {
            let hold = modifierHoldDelaySeconds()
            postKeyboard(source, tap: tap, virtualKey: leftControlVK, keyDown: true, flags: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                postKeyboard(source, tap: tap, virtualKey: key, keyDown: true, flags: .maskControl)
                postKeyboard(source, tap: tap, virtualKey: key, keyDown: false, flags: .maskControl)
                postKeyboard(source, tap: tap, virtualKey: leftControlVK, keyDown: false, flags: [])
                Logger.debug(
                    "posted ctrl+arrow (explicit modifiers, hold=\(Int(hold * 1000))ms) keyCode=\(key) tap=\(useHID ? "hid" : "session")"
                )
            }
        } else {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
            keyDown?.flags = .maskControl
            keyUp?.flags = .maskControl
            keyDown?.post(tap: tap)
            keyUp?.post(tap: tap)
            Logger.debug("posted ctrl+arrow keyCode=\(key) tap=\(useHID ? "hid" : "session") source=\(useHID ? "hidSystem" : "combinedSession")")
        }
    }
}
