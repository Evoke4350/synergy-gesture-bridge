import Foundation

let env = ProcessInfo.processInfo.environment
let listenMode = env["SGB_LISTEN"] == "1" || CommandLine.arguments.contains("--listen")

if listenMode {
    let port = NetworkBridge.port
    Logger.boot("listen mode starting on udp/\(port)…")

    let listener: UDPListener
    do {
        listener = try UDPListener(port: port) { direction in
            Logger.debug("forwarding to local Ctrl+\(direction.label)")
            KeySynthesizer.postControlArrow(direction.arrowKey)
        }
    } catch {
        Logger.error("failed to bind udp/\(port): \(error)")
        exit(1)
    }
    listener.start()
    Logger.debug("udp listener bound on 0.0.0.0:\(port)")

    print("synergy-gesture-bridge --listen running on udp/\(port).")
    print("on each datagram (1 byte: L/R/U/D + \\n): post local Ctrl+Arrow → switches Spaces / Mission Control natively.")
    print("requires Accessibility permission for this binary on this client Mac.")
    print("requires Mission Control shortcuts enabled: System Settings > Keyboard > Keyboard Shortcuts > Mission Control.")
    print("set SGB_PORT to override port; set SGB_VERBOSE=1 for debug logs.")

    RunLoop.current.run()
} else {
    Logger.boot("starting…")
    let sender = UDPSender(host: NetworkBridge.clientHost, port: NetworkBridge.port)
    let coordinator = BridgeCoordinator(emitKey: { key in
        guard let direction = NetworkBridge.Direction(arrowKey: key) else {
            Logger.debug("no direction mapping for keyCode=\(key) — dropping")
            return
        }
        sender.send(direction)
    })
    let tap = SwipeEventTap { deltaX, deltaY in
        coordinator.handle(deltaX: deltaX, deltaY: deltaY)
    }

    do {
        try tap.start()
    } catch {
        Logger.error(String(describing: error))
        exit(1)
    }

    Logger.debug("event tap installed; verbose logging is on")
    Logger.debug("UDP forwarder host=\(sender.host) port=\(sender.port)")
    print("synergy-gesture-bridge running.")
    print("Server trackpad: 3-finger (Swipe between pages) or 4-finger (Swipe between full-screen apps) -> UDP packet to client; client runs `synergy-gesture-bridge --listen` and synthesizes Ctrl+Arrow locally.")
    print("Trackpad: More Gestures must match (e.g. four fingers for fullscreen apps, three for pages).")
    print("set SGB_VERBOSE=1 for debug logs.")
    print("required for Synergy 3 (which drops synthesized CGEvents): run this binary on BOTH Macs — server normal, client with `--listen` (or `SGB_LISTEN=1`).")
    print("network: SGB_CLIENT_HOST=<client-ip> (default 255.255.255.255 broadcast); SGB_PORT=<port> (default 51237).")
    print("optional: SGB_ASSUME_CLIENT=1 or SGB_REMOTE_SWIPES=1 if the host cursor stays in-screen while on a client (disables native Spaces swipes on the server); SGB_EDGE_MARGIN (default 20); SGB_EDGE_TOP_BOTTOM=1.")
    print("If no swipe logs while the pointer is on a Synergy client, try SGB_TAP_LOCATION=hid or SGB_TAP_LOCATION=annotated (session Dock gestures may not be delivered in that state).")
    print("Exit 137: macOS SIGKILLs this unsigned tool from /usr/local/bin. If you use ~/.local/bin, run `which synergy-gesture-bridge` — if it is still under /usr/local, remove that binary or put ~/.local/bin first in PATH, then `hash -r`.")

    RunLoop.current.run()
}
