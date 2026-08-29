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
set -uo pipefail

f="$1"; content="$2"
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
