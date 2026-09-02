#!/usr/bin/env bash
# Atomic, symlink-safe writes for the control-panel plugin.
# Args: <target-lua-path>  <content>
#
# SECURITY (Omarchy marketplace review, HEAD d6f3a1c follow-up):
# - Both file writes use an EXCLUSIVE mktemp temp in the SAME directory + mv -f
#   (atomic; a planted symlink on a fixed name cannot redirect the write).
# - NO `>>` shell redirection anywhere (that is the symlink-append vector).
# - Every read is byte-capped with `timeout 5 head -c 65536` so a huge or
#   FIFO/hostile file cannot hang the helper or exhaust memory.
#
# IDEMPOTENT: if the new content is byte-identical to the existing file, skip
# the write entirely. Otherwise Quickshell/Omarchy's file-watch on ~/.config/hypr
# sees a changed mtime on every refresh and reloads the plugin in a loop, which
# makes Hyprland re-register binds/config and "jumps" the windows.
set -uo pipefail

f="$1"; content="$2"

# If the file already exists with identical content, do nothing (keep mtime).
if [ -f "$f" ]; then
  existing="$(timeout 5 head -c 65536 "$f" 2>/dev/null)"
  if [ "$existing" = "$content" ]; then
    exit 0
  fi
fi

d="$(dirname -- "$f")"
TMP="$(mktemp "$d/.ocp-lua.XXXXXX")"
chmod 644 "$TMP" 2>/dev/null || true
printf '%s\n' "$content" > "$TMP"
mv -f "$TMP" "$f"

# NOTE: hyprland.lua already requires("control-panel") (the plugin's generated
# Lua). We do NOT touch hyprland.lua here — re-inserting require("hypr.control-panel")
# created a DUPLICATE require, which executed control-panel.lua twice per reload
# and produced the "Gesture will be overshadowed by a previous gesture" warning.
# The single require("control-panel") is sufficient and must stay unique.
