# synergy-gesture-bridge

Forward macOS three-finger trackpad swipes across Synergy (Symless) to the client machine. Switch Spaces and trigger Mission Control on a Synergy-controlled Mac with the same gestures you use locally.

Synergy's wire protocol only carries keyboard and mouse events — multi-touch gestures are dropped. This tiny daemon intercepts three-finger swipe events on the **server** machine (the one with the physical trackpad), checks whether Synergy has the cursor on a client screen, and translates the gesture into a `Ctrl+Arrow` keystroke that Synergy forwards natively. Client macOS then switches Spaces or opens Mission Control as if the gesture happened locally.

Zero dependencies. Pure Swift. MIT licensed. Free as in "pay $22 for BetterTouchTool? no thanks."

## Features

- **Three-finger swipe left/right** → `Ctrl+←` / `Ctrl+→` (switch Spaces on client)
- **Three-finger swipe up/down** → `Ctrl+↑` / `Ctrl+↓` (Mission Control / app windows)
- **Conditional activation** — only fires when Synergy is running *and* cursor is on a client display. Your local gestures behave normally.
- **Event consumption** — server doesn't also switch Spaces when gesture is forwarded.
- **No private frameworks** — uses only public `CGEventTap` + `NSEvent` APIs.

## Requirements

- macOS 12+
- Swift 5.9+ toolchain (`xcode-select --install`)
- Synergy / Synergy 3 (Symless) installed and running as server
- Trackpad setting: **System Settings → Trackpad → More Gestures → Swipe between pages → "Swipe with three fingers"**

## Install

```bash
git clone https://github.com/Evoke4350/synergy-gesture-bridge.git
cd synergy-gesture-bridge
swift build -c release
sudo cp .build/release/SynergyGestureBridge /usr/local/bin/synergy-gesture-bridge
```

Grant Accessibility permission on first run: **System Settings → Privacy & Security → Accessibility → add `synergy-gesture-bridge`**.

## Run

```bash
synergy-gesture-bridge
```

Debug mode:

```bash
SGB_VERBOSE=1 synergy-gesture-bridge
```

## Autostart (launchd)

Create `~/Library/LaunchAgents/com.evoke4350.synergy-gesture-bridge.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.evoke4350.synergy-gesture-bridge</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/synergy-gesture-bridge</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
```

Load:

```bash
launchctl load ~/Library/LaunchAgents/com.evoke4350.synergy-gesture-bridge.plist
```

## How it works

1. Registers a `CGEventTap` on session-level event stream for `NSEventTypeSwipe` (type 31).
2. On each swipe event, checks:
   - Synergy process is running (walks `NSWorkspace.runningApplications`)
   - Mouse cursor is outside all physical display frames (Synergy parks cursor in virtual coords when on a client)
3. If both true, reads `deltaX` / `deltaY` from the synthesized `NSEvent`, posts the corresponding `Ctrl+Arrow` keystroke via `CGEventPost`, and returns `nil` from the tap to consume the original gesture so the server doesn't also switch Spaces.
4. Otherwise passes the event through unchanged.

## Troubleshooting

- **Nothing happens** — enable `SGB_VERBOSE=1`. If no swipe logs appear, Trackpad setting is wrong (see Requirements). If logs appear but ctrl+arrow does nothing on client, verify the client's keyboard shortcuts for Spaces are enabled (System Settings → Keyboard → Keyboard Shortcuts → Mission Control).
- **Gesture also switches Space on server** — event tap not consuming. Check for conflicting tools (BetterTouchTool, Karabiner gesture rules).
- **Daemon quits with "failed to create event tap"** — Accessibility permission missing.
- **Swipe direction feels inverted** — flip the `dx > 0` comparison in `main.swift` or open an issue.

## Alternatives

- [BetterTouchTool](https://folivora.ai/) — $22, polished GUI, does this plus a thousand other things.
- [Hammerspoon](https://www.hammerspoon.org/) — free, Lua-scriptable, but gesture capture on modern macOS is finicky.

This project exists because neither felt right for a single 80-line use case.

## Keywords

synergy, symless, synergy kvm, synergy 3, macOS trackpad gestures, three finger swipe, forward gestures synergy, mission control synergy, spaces switcher, multi-monitor kvm, kvm software, macOS gesture bridge, CGEventTap swipe, NSEventTypeSwipe, multi-mac productivity

## License

MIT — see [LICENSE](LICENSE).
