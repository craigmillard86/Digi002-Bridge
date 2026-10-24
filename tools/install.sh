#!/bin/bash
# Builds the release bridge and installs it as /usr/local/bin/digi002-bridge.
# With --login, also installs a launch agent so it starts at login and runs in the
# background (log: ~/Library/Logs/digi002-bridge.log).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
dest=/usr/local/bin/digi002-bridge
if [ -w /usr/local/bin ]; then
    cp .build/release/bridge "$dest"
else
    sudo cp .build/release/bridge "$dest"
fi
echo "installed $dest"

if [ "${1:-}" = "--login" ]; then
    plist="$HOME/Library/LaunchAgents/com.digi002.bridge.plist"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    sed "s|@BINARY@|$dest|g; s|@HOME@|$HOME|g" tools/com.digi002.bridge.plist > "$plist"
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
    echo "launch agent installed: $plist"
    echo "log: $HOME/Library/Logs/digi002-bridge.log"
fi
