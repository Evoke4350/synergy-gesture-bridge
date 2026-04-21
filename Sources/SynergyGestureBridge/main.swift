import Foundation

let coordinator = BridgeCoordinator()
let tap = SwipeEventTap { deltaX, deltaY in
    coordinator.handle(deltaX: deltaX, deltaY: deltaY)
}

do {
    try tap.start()
} catch {
    Logger.error(String(describing: error))
    exit(1)
}

print("synergy-gesture-bridge running.")
print("3-finger swipe on server trackpad -> ctrl+arrow forwarded via Synergy to the active client.")
print("requires: Trackpad > More Gestures > 'Swipe between pages' set to 'Swipe with three fingers'.")
print("set SGB_VERBOSE=1 for debug logs.")

RunLoop.current.run()
