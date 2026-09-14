#!/bin/bash
# Control Panel Desktop — standalone, reusable, always brought to front.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/desktop"
[ -z "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY="wayland-1"
[ -z "$XDG_RUNTIME_DIR" ] && export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Hyprctl needs HYPRLAND_INSTANCE_SIGNATURE; a quickshell daemonized from an
# arbitrary terminal (SSH, TTY, this script) may not have it. Resolve it from
# the live instances (stale dirs from crashed/killed sessions don't answer).
if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
  for d in $(ls -t "${XDG_RUNTIME_DIR}/hypr" 2>/dev/null); do
    [ -S "${XDG_RUNTIME_DIR}/hypr/$d/.socket.sock" ] || continue
    if timeout 2 hyprctl -i "$d" version >/dev/null 2>&1; then
      export HYPRLAND_INSTANCE_SIGNATURE="$d"
      break
    fi
  done
fi

# If the window already exists, focus it using the Sensei/Lua dispatcher API.
# Raw `hyprctl dispatch focuswindow ...` is invalid on Omarchy 4 and was why a
# click appeared to do nothing while the panel remained behind other windows.
if pgrep -f "quickshell.*control-panel.*shell.qml" >/dev/null 2>&1; then
  ADDR=$(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.title == "Control Panel") | .address' | tr -d '\n')
  if [ -n "$ADDR" ]; then
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:$ADDR' })); hl.dispatch(hl.dsp.window.bring_to_top()); hl.dispatch(hl.dsp.window.center())" >/dev/null
    exit 0
  fi
  # A process without a mapped client is stale; replace it instead of silently
  # returning and leaving the bar button dead.
  pkill -f "quickshell.*control-panel.*shell.qml" 2>/dev/null || true
fi

# Lanzar nueva instancia
cd "$DIR"
export QML2_IMPORT_PATH="$DIR:/usr/share/omarchy/shell:/usr/lib/qt6/qml"
export QML_IMPORT_PATH="$DIR:/usr/share/omarchy/shell:/usr/lib/qt6/qml"
exec quickshell --daemonize -p "$DIR/shell.qml"
