#!/usr/bin/env bash
# Install a glibc locale as root (invoked via pkexec from Panel.qml).
# Args: <locale>  e.g. es_MX.UTF-8
#
# SECURITY: edits to /etc/locale.gen use an EXCLUSIVE mktemp temp + mv -f
# (atomic; a planted symlink on a fixed name cannot redirect the write, and
# there is NO `>>` append — the symlink-append vector). The read is byte-capped
# with `timeout 5 head -c 65536` so a huge/hostile file cannot hang this.
set -uo pipefail
v="$1"
[ -n "$v" ] || exit 1
f=/etc/locale.gen
d="$(dirname -- "$f")"
cur="$(timeout 5 head -c 65536 "$f" 2>/dev/null || true)"
# Enable the locale line (strip a leading '#'), add it if missing.
cur="$(printf '%s\n' "$cur" | sed "/^#\? *${v} UTF-8/s/^# *//")"
if ! printf '%s\n' "$cur" | grep -q "^${v} UTF-8"; then
  cur="${cur}
${v} UTF-8"
fi
TMP="$(mktemp "$d/.ocp-locale.XXXXXX")"
chmod 644 "$TMP" 2>/dev/null || true
printf '%s\n' "$cur" > "$TMP"
mv -f "$TMP" "$f"
locale-gen
localectl set-locale "$v"
echo "DONE:$v"
