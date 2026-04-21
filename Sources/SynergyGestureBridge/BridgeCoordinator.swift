import CoreGraphics

/// Glues policy (when to act) and action (what to send) together.
///
/// Given a swipe delta, the coordinator decides whether to forward a keystroke
/// based on Synergy state and cursor location, then delegates the translation
/// to `GestureTranslator` and the emission to `KeySynthesizer`.
struct BridgeCoordinator {
    let translator: GestureTranslator
    let isSynergyRunning: () -> Bool
    let isCursorOnClient: () -> Bool
    let emitKey: (CGKeyCode) -> Void

    init(
        translator: GestureTranslator = GestureTranslator(),
        isSynergyRunning: @escaping () -> Bool = SynergyDetector.isRunning,
        isCursorOnClient: @escaping () -> Bool = CursorLocator.isOnClientScreen,
        emitKey: @escaping (CGKeyCode) -> Void = KeySynthesizer.postControlArrow
    ) {
        self.translator = translator
        self.isSynergyRunning = isSynergyRunning
        self.isCursorOnClient = isCursorOnClient
        self.emitKey = emitKey
    }

    func handle(deltaX: CGFloat, deltaY: CGFloat) -> SwipeEventTap.Decision {
        guard isSynergyRunning() else {
            Logger.debug("synergy not running — passthrough")
            return .passthrough
        }
        guard isCursorOnClient() else {
            Logger.debug("cursor on server — passthrough")
            return .passthrough
        }
        guard let key = translator.arrowKey(forDeltaX: deltaX, deltaY: deltaY) else {
            Logger.debug("swipe below threshold dx=\(deltaX) dy=\(deltaY) — passthrough")
            return .passthrough
        }
        Logger.debug("swipe dx=\(deltaX) dy=\(deltaY) -> keyCode=\(key)")
        emitKey(key)
        return .consume
    }
}
