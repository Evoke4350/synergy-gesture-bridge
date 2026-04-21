import CoreGraphics

/// Maps a 2-D swipe delta onto a corresponding arrow-key direction.
///
/// Returns `nil` when neither axis clears the configured threshold, so the caller
/// can pass the original event through to macOS untouched.
struct GestureTranslator {
    let horizontalThreshold: CGFloat
    let verticalThreshold: CGFloat

    init(horizontalThreshold: CGFloat = 0.5, verticalThreshold: CGFloat = 0.5) {
        self.horizontalThreshold = horizontalThreshold
        self.verticalThreshold = verticalThreshold
    }

    func arrowKey(forDeltaX dx: CGFloat, deltaY dy: CGFloat) -> CGKeyCode? {
        if abs(dx) >= horizontalThreshold && abs(dx) >= abs(dy) {
            return dx > 0 ? ArrowKey.left : ArrowKey.right
        }
        if abs(dy) >= verticalThreshold {
            return dy > 0 ? ArrowKey.up : ArrowKey.down
        }
        return nil
    }
}
