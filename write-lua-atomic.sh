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

# Idempotently ensure ~/.config/hypr/hyprland.lua requires control-panel, using
# the SAME atomic + byte-capped + FIFO-safe pattern. No unbounded grep, no '>>'.
hl="$HOME/.config/hypr/hyprland.lua"
hld="$(dirname -- "$hl")"
mkdir -p -- "$hld"
if [ -f "$hl" ]; then
  cur="$(timeout 5 head -c 65536 "$hl" 2>/dev/null || true)"
  if ! printf '%s' "$cur" | grep -qs 'require("control-panel")'; then
    TMP2="$(mktemp "$hld/.ocp-hl.XXXXXX")"
    chmod 644 "$TMP2" 2>/dev/null || true
    printf '%s\nrequire("control-panel")\n' "$cur" > "$TMP2"
    mv -f "$TMP2" "$hl"
  fi
else
  TMP2="$(mktemp "$hld/.ocp-hl.XXXXXX")"
  chmod 644 "$TMP2" 2>/dev/null || true
  printf 'require("control-panel")\n' > "$TMP2"
  mv -f "$TMP2" "$hl"
fi
