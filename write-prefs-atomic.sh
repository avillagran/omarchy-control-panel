#!/usr/bin/env bash
# Atomic, symlink-safe write of the plugin prefs JSON.
# Args: <target-path>  <content>
# Exclusive temp in the same directory (mktemp, O_EXCL) prevents a planted
# symlink on a predictable name from redirecting the write; mv -f is atomic.
set -euo pipefail
f="$1"; content="$2"
d="$(dirname -- "$f")"
mkdir -p -- "$d"
TMP="$(mktemp "$d/.ocp-prefs.XXXXXX")"
chmod 644 "$TMP" 2>/dev/null || true
printf '%s\n' "$content" > "$TMP"
mv -f "$TMP" "$f"
