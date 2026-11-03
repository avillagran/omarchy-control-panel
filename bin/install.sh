#!/usr/bin/env bash
# Install the ready-to-use panel. Experimental compositor trials are separate.
set -euo pipefail
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
ref="${OMARCHY_PANEL_REF:-5f3d41e4719d95e7749c7b86602ede38bb1cb6e7}"
[[ $ref =~ ^[0-9a-f]{40}$ ]] || { echo "Expected a full immutable OMARCHY_PANEL_REF" >&2; exit 2; }
id=io.github.avillagran.omarchy-control-panel
plugins="$HOME/.config/omarchy/plugins"
target="$plugins/$id"
for command in git python3 omarchy omarchy-shell quickshell hyprctl jq timeout; do
  command -v "$command" >/dev/null || { echo "Missing dependency: $command" >&2; exit 1; }
done
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  for socket in "$XDG_RUNTIME_DIR"/hypr/*/.socket.sock; do
    [[ -S $socket ]] || continue
    instance=${socket%/.socket.sock}
    instance=${instance##*/}
    if timeout 2 hyprctl -i "$instance" version >/dev/null 2>&1; then
      export HYPRLAND_INSTANCE_SIGNATURE="$instance"
      break
    fi
  done
fi
hyprctl -j clients >/dev/null || { echo "Run this installer in your active Omarchy desktop session." >&2; exit 1; }
[[ ! -L $target ]] || { echo "Plugin is a symlink; preserve your development checkout." >&2; exit 1; }
mkdir -p "$plugins"
stage=$(mktemp -d "$plugins/.control-panel.XXXXXX")
trap 'rm -rf "$stage"' EXIT
git -C "$stage" init -q
git -C "$stage" remote add origin https://github.com/avillagran/omarchy-control-panel.git
git -C "$stage" fetch --depth 1 origin "$ref"
git -C "$stage" checkout -q --detach "$ref"
[[ $(git -C "$stage" rev-parse HEAD) == "$ref" ]] || exit 1
omarchy plugin validate "$stage"
if [[ -e $target ]]; then
  backups="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-control-panel/plugin-backups"
  mkdir -p "$backups"
  backup=$(mktemp -d "$backups/before-panel-install.XXXXXX")
  rmdir "$backup"
  mv "$target" "$backup"
  if ! mv "$stage" "$target"; then
    mv "$backup" "$target"
    exit 1
  fi
  echo "Previous plugin preserved in $backup"
else
  mv "$stage" "$target"
fi
omarchy-shell shell rescanPlugins >/dev/null
discovered=false
for ((attempt=0; attempt<100; attempt++)); do
  if omarchy plugin list --json | python3 -c 'import json,sys; sys.exit(0 if any(p.get("id")==sys.argv[1] for p in json.load(sys.stdin)) else 1)' "$id"; then
    discovered=true
    break
  fi
  sleep 0.05
done
[[ $discovered == true ]] || { echo "Shell did not discover the panel." >&2; exit 1; }
omarchy plugin enable "$id" --section right
bash "$target/bin/toggle-desktop.sh"
for ((attempt=0; attempt<100; attempt++)); do
  if hyprctl -j clients | python3 -c 'import json,sys; sys.exit(0 if any(c.get("title")=="Control Panel" and c.get("mapped", True) for c in json.load(sys.stdin)) else 1)'; then
    echo "Control Panel installed, enabled and opened."
    exit 0
  fi
  sleep 0.1
done
echo "Panel installed but its window did not appear; check the Quickshell log." >&2
exit 1
