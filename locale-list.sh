#!/usr/bin/env bash
# Emit available glibc locales as "value<TAB>installed(0|1)" lines.
# Used by Panel.qml localeListProc to populate the language picker.
set -u
gen=$(locale -a 2>/dev/null | sed -E 's/\.utf8$/\.UTF-8/I; s/\.utf-8$/\.UTF-8/I' | sort -u)
for b in $(ls /usr/share/i18n/locales/ 2>/dev/null); do
  if echo "$b" | grep -qE '^[a-z]{2}(_[A-Z]{2})?$'; then
    v="${b}.UTF-8"
    if echo "$gen" | grep -qx "$v"; then echo "$v	1"; else echo "$v	0"; fi
  fi
done
