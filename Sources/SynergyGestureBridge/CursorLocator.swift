import AppKit
import Foundation

/// Determines whether the mouse cursor should be treated as "on a Synergy client"
/// for gesture forwarding.
///
/// Historically Synergy parked the pointer outside every `NSScreen` frame; many builds
/// now clamp it just inside the **outer** desktop edge. Some builds leave it **well
/// inside** the panel while the pointer is remote, so geometry alone is unreliable.
///
/// Use **`SGB_ASSUME_CLIENT=1`** or **`SGB_REMOTE_SWIPES=1`** (or `true` / `yes` / `on`)
/// to always treat the cursor as on the client whenever Synergy is running (you lose
/// native Spaces swipes on the **server** while that is set).
enum CursorLocator {
    private static func truthy(_ raw: String?) -> Bool {
        guard let raw else { return false }
        switch raw.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    /// When set, always treat the cursor as on the client whenever Synergy is running.
    static var forceClientCursor: Bool {
        truthy(ProcessInfo.processInfo.environment["SGB_ASSUME_CLIENT"])
            || truthy(ProcessInfo.processInfo.environment["SGB_REMOTE_SWIPES"])
    }

    private static var edgeMargin: CGFloat {
        let env = ProcessInfo.processInfo.environment["SGB_EDGE_MARGIN"] ?? ""
        guard let v = Double(env), v > 0, v < 500 else { return 20 }
        return CGFloat(v)
    }

    static func isOnClientScreen() -> Bool {
        if forceClientCursor {
            Logger.debug("SGB_ASSUME_CLIENT / SGB_REMOTE_SWIPES — treating cursor as on client")
            return true
        }

        let location = NSEvent.mouseLocation
        let screens = NSScreen.screens
        if screens.isEmpty {
            return true
        }

        let frames = screens.map(\.frame)
        if !frames.contains(where: { $0.contains(location) }) {
            Logger.debug("mouse outside all NSScreen frames — on client")
            return true
        }

        var union = frames[0]
        for i in 1 ..< frames.count {
            union = union.union(frames[i])
        }

        let m = edgeMargin
        let distOuterLeft = location.x - union.minX
        let distOuterRight = union.maxX - location.x
        let distOuterBottom = location.y - union.minY
        let distOuterTop = union.maxY - location.y

        let nearLeftRight = distOuterLeft <= m || distOuterRight <= m
        let nearTopBottom = distOuterBottom <= m || distOuterTop <= m

        if nearLeftRight {
            Logger.debug(
                "mouse near desktop outer left/right (≤\(m)pt) — on client loc=\(location) union x=[\(union.minX),\(union.maxX)]"
            )
            return true
        }

        if ProcessInfo.processInfo.environment["SGB_EDGE_TOP_BOTTOM"] == "1", nearTopBottom {
            Logger.debug(
                "mouse near desktop outer top/bottom (≤\(m)pt) — on client loc=\(location)"
            )
            return true
        }

        Logger.debug(
            "cursor treated as on SERVER — passthrough. mouse=\(location) dist to outer union: L=\(distOuterLeft) R=\(distOuterRight) B=\(distOuterBottom) T=\(distOuterTop) (margin=\(m)). If Synergy hides the host cursor while on a client, set SGB_ASSUME_CLIENT=1 or SGB_REMOTE_SWIPES=1."
        )
        return false
    }
}
