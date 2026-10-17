#!/bin/bash
# Bootstrap the reviewed Omarchy tooltip trial. The core installer owns package
# installation, selective overlay, state, and rollback; this file only pins source.
set -euo pipefail

OMARCHY_REPO="https://github.com/omacom/omarchy.git"
# Reviewed Omarchy PR #15694. Keep the exact source revision immutable.
OMARCHY_TOOLTIP_COMMIT="0cf7154757b4cfa31400df676f4d620c88659b63"
OMARCHY_TOOLTIP_PR="15694"
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy
state_file=$state_dir/tooltip-trial.json
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/tooltip-source

if [[ ${1:-} == "--uninstall" && $# == 1 ]]; then
  if [[ ! -f $state_file ]]; then
    printf '%s\n' "No tooltip trial installed by this command."
    exit 0
  fi
  # Use the exact source copied into the installed trial; do not fetch an
  # unrelated future PR head while undoing an existing installation.
  source_script=$(python3 - "$state_file" <<'PY'
import json, sys
from pathlib import Path
state = json.loads(Path(sys.argv[1]).read_text())
print(Path(state['trialOmarchy']) / 'bin/omarchy-install-tooltips')
PY
)
  [[ -f $source_script ]] || { printf 'Rollback script missing: %s\n' "$source_script" >&2; exit 1; }
  OMARCHY_PATH=$(dirname "$(dirname "$source_script")") bash "$source_script" --uninstall
  exit
fi
[[ $# == 0 ]] || { printf 'Usage: install-tooltip-patch.sh [--uninstall]\n' >&2; exit 2; }
[[ $OMARCHY_TOOLTIP_COMMIT =~ ^[0-9a-fA-F]{40}$ ]] || {
  printf 'Omarchy tooltip PR is not published: replace OMARCHY_TOOLTIP_COMMIT with its verified 40-character SHA (PR %s).\n' "$OMARCHY_TOOLTIP_PR" >&2
  exit 1
}
base_root=${OMARCHY_PATH:-/usr/share/omarchy}
[[ -d $base_root/shell && -d $base_root/default ]] || { printf 'Invalid active Omarchy tree: %s\n' "$base_root" >&2; exit 1; }
mkdir -p "$cache_dir"
source_dir=$cache_dir/${OMARCHY_TOOLTIP_COMMIT,,}
if [[ ! -d $source_dir/.git ]]; then
  staging=$(mktemp -d "$cache_dir/.fetch.XXXXXX")
  trap 'rm -rf "$staging"' EXIT
  git -C "$staging" init -q
  git -C "$staging" remote add origin "$OMARCHY_REPO"
  git -C "$staging" fetch --depth 1 origin "$OMARCHY_TOOLTIP_COMMIT"
  fetched=$(git -C "$staging" rev-parse FETCH_HEAD^{commit})
  [[ $fetched == "${OMARCHY_TOOLTIP_COMMIT,,}" ]] || { printf 'Omarchy SHA mismatch: %s\n' "$fetched" >&2; exit 1; }
  git -C "$staging" checkout -q --detach "$fetched"
  mv "$staging" "$source_dir"
  trap - EXIT
fi
[[ $(git -C "$source_dir" rev-parse HEAD) == "${OMARCHY_TOOLTIP_COMMIT,,}" ]] || { printf 'Cached Omarchy SHA mismatch. Refusing.\n' >&2; exit 1; }
[[ -z $(git -C "$source_dir" status --porcelain) ]] || { printf 'Cached Omarchy source is dirty. Refusing.\n' >&2; exit 1; }
[[ -f $source_dir/bin/omarchy-install-tooltips ]] || { printf 'Pinned Omarchy commit has no tooltip installer.\n' >&2; exit 1; }
OMARCHY_PATH=$source_dir bash "$source_dir/bin/omarchy-install-tooltips" --base "$base_root"
