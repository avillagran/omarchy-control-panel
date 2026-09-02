#!/bin/bash
# Control Panel Desktop Launcher
# Usage: bash bin/launch-desktop.sh

DIR="$(cd "$(dirname "$0")/.." && pwd)/desktop"

# Kill existing
pkill -f "quickshell.*control-panel.*shell.qml" 2>/dev/null
sleep 0.2

# Launch with proper environment
cd "$DIR"
export QML2_IMPORT_PATH="$DIR/qs:/usr/share/omarchy/shell:/usr/lib/qt6/qml"
export QML_IMPORT_PATH="$DIR/qs:/usr/share/omarchy/shell:/usr/lib/qt6/qml"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1001}"

exec quickshell -p "$DIR/shell.qml"
