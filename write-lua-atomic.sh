#!/usr/bin/env bash
# Atomic, symlink-safe write of the control-panel.lua file.
# Args: <target-path>  <content>
# Creates an exclusive temp in the SAME directory (mktemp, O_EXCL) so a planted
# symlink on a predictable name cannot redirect the write, then mv -f (atomic).
set -euo pipefail
f="$1"; content="$2"
d="$(dirname -- "$f")"
TMP="$(mktemp "$d/.ocp-lua.XXXXXX")"
chmod 644 "$TMP" 2>/dev/null || true
printf '%s\n' "$content" > "$TMP"
mv -f "$TMP" "$f"
# Ensure the plugin is required by hyprland.lua (idempotent).
hl="$HOME/.config/hypr/hyprland.lua"
if [ -f "$hl" ] && ! grep -qs 'require("control-panel")' "$hl"; then
  printf 'require("control-panel")\n' >> "$hl"
fi
