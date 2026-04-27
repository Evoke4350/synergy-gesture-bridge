import AppKit
import CoreGraphics

/// Installs a `CGEventTap` that intercepts trackpad swipes used for Spaces / Mission
/// Control and routes them through the injected handler.
///
/// Recent macOS releases deliver these as session-level Dock / gesture events (see
/// open-source references such as joshuarli/iss), not as `NSEventTypeSwipe` on a HID
/// tap. We default to `CGEventTapLocation.cgSessionEventTap`. When Synergy parks the
/// pointer on a client, some setups stop delivering those gestures on the session tap;
/// try **`SGB_TAP_LOCATION=hid`** or **`annotated`** (see `eventTapLocation()`).
final class SwipeEventTap {
    /// Raw value of `NSEventTypeSwipe` — not exposed in the public Swift enum.
    static let swipeEventRawType: UInt32 = 31

    /// Result returned by the handler: either consume the event or pass it through.
    enum Decision {
        case consume
        case passthrough
    }

    typealias Handler = (_ deltaX: CGFloat, _ deltaY: CGFloat) -> Decision

    private let handler: Handler
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Undocumented integer fields used by WindowServer for gesture routing (same IDs
    /// as documented in community tools that reverse-engineered the stream).
    private enum CGSessionField {
        static let cgsEventType = CGEventField(rawValue: 55)!
        static let gestureHIDType = CGEventField(rawValue: 110)!
        static let gestureSwipeMotion = CGEventField(rawValue: 123)!
        static let gestureSwipeProgress = CGEventField(rawValue: 124)!
        static let gestureSwipeVelocityX = CGEventField(rawValue: 129)!
        static let gestureSwipeVelocityY = CGEventField(rawValue: 130)!
        static let gesturePhase = CGEventField(rawValue: 132)!
    }

    private enum CGSSemanticEventType: Int64 {
        case gesture = 29
        case dockControl = 30
    }

    /// `IOHIDEventType` values for navigation / dock swipe (IOHIDFamily).
    private enum IOHIDGestureType: Int64 {
        case navigationSwipe = 16
        case dockSwipe = 23
    }

    private enum GesturePhase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
        case cancelled = 8
    }

    /// Dock swipe routing: 1 = horizontal (Spaces), 2 = vertical (Mission Control / Exposé).
    private enum DockSwipeMotion: Int64 {
        case horizontal = 1
        case vertical = 2
    }

    private var dockSwipeSessionActive = false
    private var dockSwipeEmittedDirection = false
    private var dockSwipeSuppressing = false

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    private func eventTapLocation() -> CGEventTapLocation {
        switch ProcessInfo.processInfo.environment["SGB_TAP_LOCATION"]?.lowercased() ?? "" {
        case "hid":
            return .cghidEventTap
        case "annotated", "annotation":
            return .cgAnnotatedSessionEventTap
        default:
            return .cgSessionEventTap
        }
    }

    /// Starts the tap. Throws if macOS refuses to create it (typically missing
    /// Accessibility permission).
    func start() throws {
        let mask: CGEventMask = (CGEventMask(1) << CGSSemanticEventType.gesture.rawValue)
            | (CGEventMask(1) << CGSSemanticEventType.dockControl.rawValue)
            | (CGEventMask(1) << SwipeEventTap.swipeEventRawType)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let location = eventTapLocation()

        guard let tap = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: SwipeEventTap.trampoline,
            userInfo: userInfo
        ) else {
            throw EventTapError.creationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        Logger.debug("CGEventTap location=\(String(describing: location)) mask=gesture|dock|swipeLegacy")
    }

    enum EventTapError: Error, CustomStringConvertible {
        case creationFailed

        var description: String {
            switch self {
            case .creationFailed:
                return "failed to create event tap — grant Accessibility permission in System Settings > Privacy & Security > Accessibility."
            }
        }
    }

    // MARK: - C trampoline

    private static let trampoline: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let tap = Unmanaged<SwipeEventTap>.fromOpaque(refcon).takeUnretainedValue()
        return tap.handleTap(type: type, event: event)
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Dock-control swipes surface as tap `type` 30; `NSEvent(cgEvent:)` does not
        // understand that and logs "unrecognized type is 30" once per event if called.
        if UInt32(type.rawValue) == SwipeEventTap.swipeEventRawType,
           let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .swipe {
            return applyHandler(dx: nsEvent.deltaX, dy: nsEvent.deltaY, event: event)
        }

        let cgsType = event.getIntegerValueField(CGSessionField.cgsEventType)

        if cgsType == CGSSemanticEventType.gesture.rawValue, dockSwipeSuppressing {
            return nil
        }

        guard cgsType == CGSSemanticEventType.dockControl.rawValue else {
            return Unmanaged.passUnretained(event)
        }

        let hidType = event.getIntegerValueField(CGSessionField.gestureHIDType)
        guard hidType == IOHIDGestureType.navigationSwipe.rawValue
            || hidType == IOHIDGestureType.dockSwipe.rawValue
        else {
            return Unmanaged.passUnretained(event)
        }

        let motion = event.getIntegerValueField(CGSessionField.gestureSwipeMotion)
        let phase = event.getIntegerValueField(CGSessionField.gesturePhase)
        let progress = event.getDoubleValueField(CGSessionField.gestureSwipeProgress)
        let velX = event.getDoubleValueField(CGSessionField.gestureSwipeVelocityX)
        let velY = event.getDoubleValueField(CGSessionField.gestureSwipeVelocityY)

        switch phase {
        case GesturePhase.began.rawValue:
            dockSwipeSessionActive = true
            dockSwipeEmittedDirection = false
            dockSwipeSuppressing = false
            Logger.debug("dock swipe began hid=\(hidType) motion=\(motion)")
            if BridgeCoordinator.shouldConsumeDockSwipeBegan() {
                return nil
            }
            return Unmanaged.passUnretained(event)

        case GesturePhase.changed.rawValue:
            guard dockSwipeSessionActive else {
                return Unmanaged.passUnretained(event)
            }
            if !dockSwipeEmittedDirection,
               let (dx, dy) = Self.swipeVector(
                   motion: motion,
                   progress: progress,
                   velocityX: velX,
                   velocityY: velY,
                   allowVelocityFallback: false
               )
            {
                dockSwipeEmittedDirection = true
                switch handler(dx, dy) {
                case .consume:
                    dockSwipeSuppressing = true
                    return nil
                case .passthrough:
                    resetDockSwipeTracking()
                    return Unmanaged.passUnretained(event)
                }
            }
            return dockSwipeSuppressing ? nil : Unmanaged.passUnretained(event)

        case GesturePhase.ended.rawValue:
            guard dockSwipeSessionActive else {
                return Unmanaged.passUnretained(event)
            }
            if !dockSwipeEmittedDirection,
               let (dx, dy) = Self.swipeVector(
                   motion: motion,
                   progress: progress,
                   velocityX: velX,
                   velocityY: velY,
                   allowVelocityFallback: true
               )
            {
                dockSwipeEmittedDirection = true
                switch handler(dx, dy) {
                case .consume:
                    dockSwipeSuppressing = true
                case .passthrough:
                    break
                }
            }
            let suppress = dockSwipeSuppressing
            resetDockSwipeTracking()
            return suppress ? nil : Unmanaged.passUnretained(event)

        case GesturePhase.cancelled.rawValue:
            resetDockSwipeTracking()
            return Unmanaged.passUnretained(event)

        default:
            return dockSwipeSuppressing ? nil : Unmanaged.passUnretained(event)
        }
    }

    private func applyHandler(dx: CGFloat, dy: CGFloat, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch handler(dx, dy) {
        case .consume:
            return nil
        case .passthrough:
            return Unmanaged.passUnretained(event)
        }
    }

    private func resetDockSwipeTracking() {
        dockSwipeSessionActive = false
        dockSwipeEmittedDirection = false
        dockSwipeSuppressing = false
    }

    /// Maps Dock-control swipe fields onto the same ±1 delta convention used by
    /// `NSEventTypeSwipe` so `GestureTranslator` thresholds still apply.
    private static func swipeVector(
        motion: Int64,
        progress: Double,
        velocityX: Double,
        velocityY: Double,
        allowVelocityFallback: Bool
    ) -> (CGFloat, CGFloat)? {
        let ε = 1e-4
        if abs(progress) > ε {
            switch motion {
            case DockSwipeMotion.horizontal.rawValue:
                return (CGFloat(progress > 0 ? 1 : -1), 0)
            case DockSwipeMotion.vertical.rawValue:
                return (0, CGFloat(progress > 0 ? 1 : -1))
            default:
                return (CGFloat(progress > 0 ? 1 : -1), 0)
            }
        }
        guard allowVelocityFallback else { return nil }
        if abs(velocityX) > ε || abs(velocityY) > ε {
            switch motion {
            case DockSwipeMotion.horizontal.rawValue:
                guard abs(velocityX) > ε else { return nil }
                return (CGFloat(velocityX > 0 ? 1 : -1), 0)
            case DockSwipeMotion.vertical.rawValue:
                guard abs(velocityY) > ε else { return nil }
                return (0, CGFloat(velocityY > 0 ? 1 : -1))
            default:
                if abs(velocityX) >= abs(velocityY), abs(velocityX) > ε {
                    return (CGFloat(velocityX > 0 ? 1 : -1), 0)
                }
                if abs(velocityY) > ε {
                    return (0, CGFloat(velocityY > 0 ? 1 : -1))
                }
            }
        }
        return nil
    }
}
