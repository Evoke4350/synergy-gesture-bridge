import AppKit

/// Determines whether the mouse cursor currently resides on a Synergy client screen.
///
/// Synergy parks the cursor in virtual coordinates that fall outside every physical
/// display frame while the pointer is on a client. We treat "outside all real
/// `NSScreen` frames" as the signal that Synergy is driving a remote machine.
enum CursorLocator {
    static func isOnClientScreen() -> Bool {
        let location = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(location) {
            return false
        }
        return true
    }
}
