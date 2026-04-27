#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
bin="$bin_dir/SynergyGestureBridge"
xattr -cr "$bin" 2>/dev/null || true
codesign --force --sign - "$bin"
echo "OK: $bin (ad hoc re-signed)"
echo "Prefer: ./install-user.sh  →  ~/.local/bin  (avoid /usr/local/bin — unsigned session taps are often SIGKILL there)"
