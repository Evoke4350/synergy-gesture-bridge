import Foundation

/// Stderr logger gated by the `SGB_VERBOSE=1` environment variable.
enum Logger {
    static let verbose = ProcessInfo.processInfo.environment["SGB_VERBOSE"] == "1"

    static func debug(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        FileHandle.standardError.write("[sgb] \(message())\n".data(using: .utf8)!)
    }

    static func error(_ message: String) {
        FileHandle.standardError.write("synergy-gesture-bridge: \(message)\n".data(using: .utf8)!)
    }
}
