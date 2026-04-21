import AppKit
import CoreGraphics

/// Installs a `CGEventTap` that intercepts `NSEventTypeSwipe` events and routes
/// them through the injected handler.
///
/// The tap is the only piece of the system that talks to Core Graphics; all
/// policy decisions (should we handle this swipe? which key to send?) live in
/// dedicated types and are passed in via the handler closure.
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

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Starts the tap. Throws if macOS refuses to create it (typically missing
    /// Accessibility permission).
    func start() throws {
        let mask: CGEventMask = 1 << SwipeEventTap.swipeEventRawType
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
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
        guard UInt32(type.rawValue) == SwipeEventTap.swipeEventRawType,
              let refcon = refcon else {
            return Unmanaged.passUnretained(event)
        }
        let tap = Unmanaged<SwipeEventTap>.fromOpaque(refcon).takeUnretainedValue()
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        switch tap.handler(nsEvent.deltaX, nsEvent.deltaY) {
        case .consume:
            return nil
        case .passthrough:
            return Unmanaged.passUnretained(event)
        }
    }
}
