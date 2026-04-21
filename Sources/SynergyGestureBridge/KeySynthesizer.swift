import CoreGraphics

/// Carbon virtual key codes used by the bridge.
enum ArrowKey {
    static let left: CGKeyCode = 123
    static let right: CGKeyCode = 124
    static let down: CGKeyCode = 125
    static let up: CGKeyCode = 126
}

/// Synthesizes and posts modifier-plus-arrow keystrokes into the HID event stream.
///
/// Synergy observes these synthetic events and forwards them to the active client
/// machine, which interprets them as native macOS shortcuts (e.g. Space switch,
/// Mission Control).
enum KeySynthesizer {
    static func postControlArrow(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        keyDown?.flags = .maskControl
        keyUp?.flags = .maskControl
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        Logger.debug("posted ctrl+arrow keyCode=\(key)")
    }
}
