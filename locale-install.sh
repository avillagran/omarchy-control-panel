#!/usr/bin/env bash
# Install a glibc locale as root (invoked via pkexec from Panel.qml).
# Args: <locale>  e.g. es_MX.UTF-8
set -e
v="$1"
[ -n "$v" ] || exit 1
f=/etc/locale.gen
sed -i "/^#\? *${v} UTF-8/s/^# *//" "$f"
grep -q "^${v} UTF-8" "$f" || echo "${v} UTF-8" >> "$f"
locale-gen
echo "DONE:$v"
