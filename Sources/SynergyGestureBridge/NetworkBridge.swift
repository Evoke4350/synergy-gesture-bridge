import CoreGraphics
import Darwin
import Foundation

/// UDP-based fallback for Synergy 3, which silently drops synthesized CGEvents on
/// the server and therefore never forwards `Ctrl+Arrow` to the client.
///
/// Server mode broadcasts a 1-byte direction (`L`/`R`/`U`/`D`) over UDP. A second
/// instance of this binary running on the client with `--listen` (or `SGB_LISTEN=1`)
/// receives the datagram and synthesizes `Ctrl+Arrow` locally, so the client OS
/// fires Mission Control / Spaces natively without Synergy involvement.
///
/// Configuration:
/// - `SGB_CLIENT_HOST` — destination IP for sender (default `255.255.255.255` broadcast).
/// - `SGB_PORT`        — port for both sides (default `51237`).
enum NetworkBridge {
    static var port: UInt16 {
        if let raw = ProcessInfo.processInfo.environment["SGB_PORT"],
           let v = UInt16(raw), v > 0 {
            return v
        }
        return 51237
    }

    static var clientHost: String {
        ProcessInfo.processInfo.environment["SGB_CLIENT_HOST"] ?? "255.255.255.255"
    }

    /// Wire byte values double as ASCII so a packet is human-readable on tcpdump.
    enum Direction: UInt8 {
        case left  = 0x4C // 'L'
        case right = 0x52 // 'R'
        case up    = 0x55 // 'U'
        case down  = 0x44 // 'D'

        init?(arrowKey: CGKeyCode) {
            switch arrowKey {
            case ArrowKey.left:  self = .left
            case ArrowKey.right: self = .right
            case ArrowKey.up:    self = .up
            case ArrowKey.down:  self = .down
            default: return nil
            }
        }

        var arrowKey: CGKeyCode {
            switch self {
            case .left:  return ArrowKey.left
            case .right: return ArrowKey.right
            case .up:    return ArrowKey.up
            case .down:  return ArrowKey.down
            }
        }

        var label: String {
            switch self {
            case .left: return "left"
            case .right: return "right"
            case .up: return "up"
            case .down: return "down"
            }
        }
    }
}

/// Fire-and-forget UDP datagram sender.
final class UDPSender {
    private let fd: Int32
    private var addr: sockaddr_in
    let host: String
    let port: UInt16

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port

        fd = socket(AF_INET, SOCK_DGRAM, 0)
        precondition(fd >= 0, "socket() failed errno=\(errno)")

        var broadcast: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr(host))
    }

    deinit { close(fd) }

    func send(_ direction: NetworkBridge.Direction) {
        var bytes: [UInt8] = [direction.rawValue, 0x0A]
        let n: ssize_t = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                sendto(fd, &bytes, bytes.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if n < 0 {
            Logger.debug("UDP sendto failed errno=\(errno) host=\(host):\(port)")
        } else {
            Logger.debug("UDP sent direction=\(direction.label) host=\(host):\(port)")
        }
    }
}

/// UDP listener for client-side `--listen` mode.
final class UDPListener {
    private let fd: Int32
    let port: UInt16
    private let onDirection: (NetworkBridge.Direction) -> Void
    private var thread: Thread?

    init(port: UInt16, onDirection: @escaping (NetworkBridge.Direction) -> Void) throws {
        self.port = port
        self.onDirection = onDirection

        let s = socket(AF_INET, SOCK_DGRAM, 0)
        guard s >= 0 else { throw POSIXError(.EIO) }
        fd = s

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: in_addr_t(0))

        let result = withUnsafePointer(to: &addr) { ap in
            ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 {
            let err = errno
            close(fd)
            throw POSIXError(POSIXError.Code(rawValue: err) ?? .EIO)
        }
    }

    deinit { close(fd) }

    func start() {
        let t = Thread { [weak self] in self?.runLoop() }
        t.name = "sgb.udp.listener"
        t.start()
        thread = t
    }

    private func runLoop() {
        var buf = [UInt8](repeating: 0, count: 64)
        var fromAddr = sockaddr_in()
        var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        while true {
            let n: ssize_t = withUnsafeMutablePointer(to: &fromAddr) { ap in
                ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buf, buf.count, 0, sa, &fromLen)
                }
            }
            if n <= 0 {
                if n < 0 { Logger.debug("recvfrom failed errno=\(errno)") }
                continue
            }
            guard let raw = buf.first,
                  let direction = NetworkBridge.Direction(rawValue: raw) else {
                continue
            }
            Logger.debug("UDP rx direction=\(direction.label)")
            let cb = onDirection
            DispatchQueue.main.async {
                cb(direction)
            }
        }
    }
}
