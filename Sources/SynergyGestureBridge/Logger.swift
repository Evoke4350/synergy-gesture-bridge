import Darwin
import Foundation

/// Stderr logger gated by `SGB_VERBOSE` (default: only when value is truthy like `1`, `true`, `yes`).
enum Logger {
    private static func truthy(_ raw: String?) -> Bool {
        guard let raw else { return false }
        switch raw.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    static var verbose: Bool {
        truthy(ProcessInfo.processInfo.environment["SGB_VERBOSE"])
    }

    private static func writeLineToStderr(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
        fflush(stderr)
    }

    static func debug(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        writeLineToStderr("[sgb] \(message())")
    }

    static func error(_ message: String) {
        writeLineToStderr("synergy-gesture-bridge: \(message)")
    }

    /// Minimal stderr trace (not gated by `SGB_VERBOSE`). Use sparingly for startup diagnostics.
    static func boot(_ message: String) {
        writeLineToStderr("synergy-gesture-bridge: \(message)")
    }
}
