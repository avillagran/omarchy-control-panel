#!/usr/bin/env bash
# Close-tab-or-window: invoked by SUPER+W when the "close tab in browsers"
# toggle is enabled. If the focused window is a known web browser, simulate
# Ctrl+W (close the active tab) via wtype (Wayland) or ydotool (X11/XWayland
# fallback); otherwise close the window with hl.dsp.window.close() — the same
# default Omarchy behaviour for SUPER+W, so every non-browser window behaves
# exactly as before.
#
# The browser class may be passed as $1 (pre-detected by the Lua bind) to avoid
# re-reading the active window, which removes any focus/timing race between the
# keypress and this script running.
set -uo pipefail

LOG=/tmp/superw-debug.log
echo "$(date '+%H:%M:%S') SUPER+W triggered; HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-UNSET} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-UNSET}" >> "$LOG"

BROWSERS='chrome|chromium|chromium-browser|brave|brave-browser|firefox|firefox-esr|edge|microsoft-edge|opera|opera-browser|vivaldi|vivaldi-stable|epiphany|gnome-web'

# Prefer a class handed in by the Lua bind; otherwise read it from hyprctl.
cls_lower="${1:-}"
if [ -z "$cls_lower" ]; then
  raw=$(hyprctl activewindow -j 2>/dev/null)
  echo "$(date '+%H:%M:%S') activewindow raw: ${raw:0:200}" >> "$LOG"
  cls=$(printf '%s' "$raw" | (command -v jq >/dev/null && jq -r '.class // ""' 2>/dev/null || true))
  cls_lower=$(printf '%s' "$cls" | tr '[:upper:]' '[:lower:]')
fi
echo "$(date '+%H:%M:%S') class='$cls_lower'" >> "$LOG"

if printf '%s' "$cls_lower" | grep -qiE "$BROWSERS"; then
  echo "$(date '+%H:%M:%S') BRANCH browser -> Ctrl+W" >> "$LOG"

  # Detect whether Chromium/Chrome is running under XWayland. wtype only
  # reaches native Wayland surfaces; ydotool works at the input-device level
  # and reaches both, but needs the ydotoold daemon.
  raw=$(hyprctl activewindow -j 2>/dev/null)
  if command -v jq >/dev/null 2>&1; then
    is_xwayland=$(printf '%s' "$raw" | jq -r '.xwayland // false' 2>/dev/null || true)
  else
    is_xwayland=false
  fi
  echo "$(date '+%H:%M:%S') xwayland=$is_xwayland" >> "$LOG"

  use_ydotool=false
  if command -v wtype >/dev/null && [ "$is_xwayland" != "true" ]; then
    if wtype -M ctrl -k w -m ctrl 2>>"$LOG"; then
      echo "$(date '+%H:%M:%S') wtype ok" >> "$LOG"
    else
      echo "$(date '+%H:%M:%S') wtype failed; will try ydotool" >> "$LOG"
      use_ydotool=true
    fi
  else
    echo "$(date '+%H:%M:%S') skipping wtype (xwayland or missing)" >> "$LOG"
    use_ydotool=true
  fi

  if $use_ydotool; then
    if ! pgrep -x ydotoold >/dev/null 2>&1; then
      echo "$(date '+%H:%M:%S') starting ydotoold" >> "$LOG"
      ydotoold >> "$LOG" 2>&1 &
      sleep 0.4
    fi
    if ydotool key ctrl+w 2>>"$LOG"; then
      echo "$(date '+%H:%M:%S') ydotool ok" >> "$LOG"
    else
      echo "$(date '+%H:%M:%S') ydotool failed" >> "$LOG"
    fi
  fi
else
  echo "$(date '+%H:%M:%S') BRANCH non-browser -> killactive" >> "$LOG"
  # Close the active window with the standard Hyprland dispatcher.
  hyprctl dispatch killactive 2>>"$LOG" || echo "$(date '+%H:%M:%S') killactive failed" >> "$LOG"
fi
echo "$(date '+%H:%M:%S') done" >> "$LOG"
