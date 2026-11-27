#!/usr/bin/env bash
# Toggle qs-hyprview without opening the settings window. The renderer is an
# upstream GPL-3.0 project by Domenico Martella (dom0); this plugin only owns
# the Omarchy launcher and gesture/key binding integration. See
# THIRD_PARTY_NOTICES.md for the pinned source revision and attribution.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM_DIR="$ROOT/external/qs-hyprview"
# Upstream: https://github.com/dom0/qs-hyprview (1fdea0a). Same source as the
# external/qs-hyprview submodule: that upstream commit plus one
# Qt 6.12 import fix (fe44661) in a public fork.
UPSTREAM_REPO="https://github.com/avillagran/qs-hyprview.git"
UPSTREAM_REVISION="fe44661a95b8ab4b7f9f4c290334cf4c3c129d31"
INTEGRATION_PATCH="$ROOT/patches/qs-hyprview/0001-integration-refresh-toplevel-model.patch"
SHELL="$UPSTREAM_DIR/shell.qml"
TARGET="expose"
LAYOUT="bands"
LEGACY_SHELL="$ROOT/desktop/quickview-shell.qml"
LEGACY_TARGET="omarchy-control-panel-quickview"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  for pid in $(pgrep -x quickshell || true); do
    sig="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | awk -F= '$1=="HYPRLAND_INSTANCE_SIGNATURE"{print $2; exit}')"
    [ -n "$sig" ] && { export HYPRLAND_INSTANCE_SIGNATURE="$sig"; break; }
  done
fi

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  for d in "$XDG_RUNTIME_DIR"/hypr/*; do
    [ -S "$d/.socket.sock" ] || continue
    sig="${d##*/}"
    if timeout 1 hyprctl -i "$sig" version >/dev/null 2>&1; then
      export HYPRLAND_INSTANCE_SIGNATURE="$sig"
      break
    fi
  done
fi

# `omarchy plugin add` does not fetch submodules: fetch the pinned revision on
# first use, and never run QML from anything but that exact commit.
if [ ! -f "$SHELL" ]; then
  mkdir -p "$(dirname "$UPSTREAM_DIR")"
  git clone --quiet --no-checkout -- "$UPSTREAM_REPO" "$UPSTREAM_DIR"
  git -C "$UPSTREAM_DIR" checkout --quiet --detach "$UPSTREAM_REVISION"
fi
if [ "$(git -C "$UPSTREAM_DIR" rev-parse HEAD 2>/dev/null)" != "$UPSTREAM_REVISION" ]; then
  printf 'QuickView source is not at the pinned revision %s\n' "$UPSTREAM_REVISION" >&2
  exit 1
fi

# Keep the upstream source pristine as a pinned submodule. Omarchy-specific
# behavior is carried as a separately auditable patch and applied idempotently
# both to the development checkout and to an on-demand local clone.
if git -C "$UPSTREAM_DIR" apply --reverse --check "$INTEGRATION_PATCH" >/dev/null 2>&1; then
  :
else
  git -C "$UPSTREAM_DIR" apply --check "$INTEGRATION_PATCH"
  git -C "$UPSTREAM_DIR" apply "$INTEGRATION_PATCH"
fi

call_toggle() {
  quickshell ipc -p "$SHELL" call "$TARGET" toggle "$LAYOUT" >/dev/null 2>&1
}

if call_toggle; then
  exit 0
fi

# A previously running experimental renderer must not overlap upstream's
# expose overlay. This does not restart Quickshell or Hyprland.
quickshell ipc -p "$LEGACY_SHELL" call "$LEGACY_TARGET" close >/dev/null 2>&1 || true
quickshell --daemonize -p "$SHELL"

for _ in $(seq 1 20); do
  if call_toggle; then
    exit 0
  fi
  sleep 0.05
done

printf 'QuickView did not become ready\n' >&2
exit 1
