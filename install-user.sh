#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
bin="$(swift build -c release --show-bin-path)/SynergyGestureBridge"
dest_dir="${HOME}/.local/bin"
mkdir -p "$dest_dir"
cp "$bin" "$dest_dir/synergy-gesture-bridge"
chmod +x "$dest_dir/synergy-gesture-bridge"
xattr -cr "$dest_dir/synergy-gesture-bridge" 2>/dev/null || true
codesign --force --sign - "$dest_dir/synergy-gesture-bridge"
echo "Installed: $dest_dir/synergy-gesture-bridge"

if [[ -x /usr/local/bin/synergy-gesture-bridge ]]; then
    echo ""
    echo "WARNING: /usr/local/bin/synergy-gesture-bridge also exists."
    echo "  Your shell runs whichever comes FIRST in PATH — that copy is often SIGKILL (exit 137)."
    echo "  Fix one of:"
    echo "    sudo rm /usr/local/bin/synergy-gesture-bridge"
    echo "    or put this line BEFORE any PATH that adds /usr/local/bin:"
    echo "      export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo "    then: hash -r   # zsh: forget command path cache"
fi

echo ""
echo "Add to ~/.zshrc (early, before /usr/local):"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
