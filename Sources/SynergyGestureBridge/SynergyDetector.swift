import AppKit

/// Detects whether the Symless Synergy server process is currently running.
enum SynergyDetector {
    private static let processNameHints = [
        "synergy",
        "synergy-core",
        "synergy-service",
        "synergys",
        "synergyc",
        "deskflow",
        "input leap",
        "inputleap",
        "barrier"
    ]

    private static let bundleIdHints = [
        "symless",
        "synergy",
        "deskflow",
        "inputleap",
        "barrier"
    ]

    static func isRunning() -> Bool {
        for app in NSWorkspace.shared.runningApplications {
            let name = (app.localizedName ?? "").lowercased()
            let bundle = (app.bundleIdentifier ?? "").lowercased()
            if processNameHints.contains(where: { name.contains($0) }) { return true }
            if bundleIdHints.contains(where: { bundle.contains($0) }) { return true }
        }
        return false
    }
}
