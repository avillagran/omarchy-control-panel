#!/usr/bin/env bash
# install-hyprland-scroll-patch.sh
#
# One-liner that installs the Omarchy Control Panel AND lets you try the
# touchpad scroll acceleration + coast patch (plus opt-in physical mouse-wheel
# inertia) TODAY, without waiting for the upstream PRs to merge:
#
#   See the pinned combined installer command in README.md.
#
# What it does:
#   1. Installs the omarchy-control-panel plugin (omarchy plugin add) and
#      enables its bar widget on the RIGHT side (omarchy plugin enable
#      --section right).
#   2. Enables Dev mode in the plugin prefs, which exposes the "Scroll feel"
#      card in Trackpad (presets + live sliders for the patch options).
#      Without Dev mode the plugin is unchanged for regular users.
#   3. Installs build dependencies via pacman (Arch/Omarchy only) — skipped
#      when they are already present, so reruns need no sudo.
#   4. Fetches UPSTREAM Hyprland (hyprwm/Hyprland) at a pinned commit and
#      applies the touchpad scroll patch from patches/hyprland/ IN THIS REPO.
#      No dependency on any fork or on the PRs being merged; bump HYPRLAND_PIN
#      (and regenerate the series) when upstream drifts — see README.
#   5. Builds Hyprland from the patched source (~5-15 min).
#   6. Installs it as a reversible "shadow" binary at ~/.local/bin/Hyprland,
#      which takes precedence over /usr/bin/Hyprland via PATH (pacman updates
#      never touch it).
#   7. Adds a PATH hook to the shell profile files (idempotent).
#   8. Appends a gated block to ~/.config/hypr/input.lua that only applies the
#      new options when the RUNNING compositor is the shadow binary, so stock
#      Hyprland never sees unknown config keys.
#   9. Wires ~/.config/hypr/control-panel.lua (the file the panel rewrites when
#      you move the sliders) into hyprland.lua via require(), so your scroll
#      values survive logout/login.
#
# Removal:
#
#   See the pinned uninstall command in README.md.
#
# After installing or uninstalling, log out and back in for the change to take
# effect (the compositor binary is chosen at session start).

set -euo pipefail

PLUGIN_ID="io.github.avillagran.omarchy-control-panel"
PANEL_REPO="https://github.com/avillagran/omarchy-control-panel.git"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
RELEASE_TAG=${OMARCHY_PANEL_REF:-0.5}
[[ $RELEASE_TAG =~ ^([0-9a-fA-F]{40}|[a-zA-Z0-9][a-zA-Z0-9._-]*)$ ]] || { echo "Invalid OMARCHY_PANEL_REF" >&2; exit 2; }
HYPRLAND_REPO="https://github.com/hyprwm/Hyprland.git"
# Upstream commit the patch series was authored against (v0.56.0-190-g1b85c7aa).
# The patches apply cleanly to exactly this tree; refresh both together.
HYPRLAND_PIN="1b85c7aa1b5c41d906880f0f495bcd0749a23175"
PATCH_NAMES="0001-input-touchpad-scroll-acceleration-profiles.patch
0002-input-fix-std-clamp-type-mismatch-in-scroll-accel-fl.patch
0003-config-drop-input-refresh-from-scroll-accel-options.patch
0004-input-add-inertial-scroll-coasting-for-touchpads.patch
0005-input-refine-scroll-coasting-seed-defaults-drop-diag.patch
0006-input-add-scroll_ignore_classes-to-disable-accel-coa.patch
0007-ipc-fix-inverted-disabled-field-in-monitors-JSON-out.patch
0008-input-add-opt-in-mouse-wheel-scroll-feel.patch"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-control-panel"
SRC_DIR="$CACHE_ROOT/hyprland-scroll-patch"
PATCH_DIR="$CACHE_ROOT/patches"
PANEL_BACKUPS="$CACHE_ROOT/plugin-backups"
SHADOW_DIR="$HOME/.local/bin"
SHADOW="$SHADOW_DIR/Hyprland"
INPUT_LUA="$HOME/.config/hypr/input.lua"
HYPR_LUA="$HOME/.config/hypr/hyprland.lua"
PANEL_LUA="$HOME/.config/hypr/control-panel.lua"
REQUIRE_MARK='require("control-panel") -- Omarchy Control Panel scroll persistence (install-hyprland-scroll-patch.sh)'
PREFS="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/control-panel-prefs.json"
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-control-panel-scroll-patch.json"
PATH_MARK="omarchy-scroll-patch:path"
# The cache marker is set after resolving the release to its immutable SHA.

# Omarchy 4.x CLI (omarchy plugin add/enable/remove) refuses to run without
# OMARCHY_PATH; sessions launched outside the Omarchy env (SSH, TTY, cron)
# don't have it. Default to the standard install location without overriding
# an explicit value.
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

log() { printf '\033[1;36m[scroll-patch]\033[0m %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

# ---------------------------------------------------------------- preferences
# set_devmode <true|false|unset-prev>: merges devMode into the plugin prefs
# JSON atomically; prints "prev=<json>" of the previous value (or null).
set_devmode() {
  python3 - "$PREFS" "$1" <<'PY'
import json, os, sys, tempfile
path, mode = sys.argv[1], sys.argv[2]
d = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            d = json.load(f)
        if not isinstance(d, dict):
            d = {}
    except Exception:
        d = {}
prev = d.get("devMode")
if mode not in ("true", "false"):
    sys.exit("set_devmode: invalid mode " + mode)
d["devMode"] = (mode == "true")
os.makedirs(os.path.dirname(path), exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(d, f)
os.replace(tmp, path)
print("prev=" + json.dumps(prev))
PY
}

uninstall() {
  [[ -f $STATE_FILE ]] || { log "No installation state; nothing owned to remove."; exit 0; }
  python3 - "$STATE_FILE" <<'PY_CHECK' || die "Legacy installation state: use the original pinned installer to uninstall before upgrading."
import json, sys
raise SystemExit(0 if json.load(open(sys.argv[1])).get('panelSha') else 1)
PY_CHECK
  local tooltip_owned backup_dir shadow_owned shadow_backup
  tooltip_owned=$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1])).get("tooltipInstalledByUs", False)).lower())' "$STATE_FILE")
  backup_dir=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("pluginBackup", ""))' "$STATE_FILE")
  shadow_owned=$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1])).get("shadowOwned", False)).lower())' "$STATE_FILE")
  shadow_backup=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("shadowBackup", ""))' "$STATE_FILE")
  if [[ -n $backup_dir ]]; then
    [[ $backup_dir == "$PANEL_BACKUPS/"* && -d $backup_dir && -d $PLUGIN_DIR ]] || die "plugin backup or installed plugin missing; refusing rollback"
  fi
  if [[ -d $PLUGIN_DIR/.git ]]; then
    [[ -z $(git -C "$PLUGIN_DIR" status --porcelain) ]] || die "installed plugin changed since install; refusing rollback"
  fi
  if [[ -n $shadow_backup ]]; then
    [[ $shadow_backup == "$CACHE_ROOT/shadow-backups/"* && -f $shadow_backup ]] || die "original shadow backup missing; refusing rollback"
  fi
  if [[ $tooltip_owned == "true" ]]; then
    bash "$PLUGIN_DIR/bin/install-tooltip-patch.sh" --uninstall
  fi
  if [[ -n $backup_dir ]]; then
    [[ -d $PLUGIN_DIR/.git ]] || die "replacement plugin missing; refusing rollback"
    [[ -z $(git -C "$PLUGIN_DIR" status --porcelain) ]] || die "replacement plugin changed; preserve its edits before uninstalling"
    rm -rf "$PLUGIN_DIR"
    mv "$backup_dir" "$PLUGIN_DIR"
  fi
  log "Removing shadow binary $SHADOW ..."
  if [[ $shadow_owned == true ]]; then
    if [[ -n $shadow_backup ]]; then
      [[ $shadow_backup == "$CACHE_ROOT/shadow-backups/"* && -f $shadow_backup ]] || die "original shadow backup missing; refusing to discard it"
      mv -f "$shadow_backup" "$SHADOW"
    else
      rm -f "$SHADOW"
    fi
  fi

  log "Removing PATH hook from shell profiles ..."
  for profile in "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zprofile"; do
    [ -f "$profile" ] || continue
    sed -i "/# ${PATH_MARK}:start/,/# ${PATH_MARK}:end/d" "$profile"
  done

  log "Removing config block from $INPUT_LUA ..."
  [ -f "$INPUT_LUA" ] && sed -i '/-- omarchy-scroll-patch:start/,/-- omarchy-scroll-patch:end/d' "$INPUT_LUA"

  log "Removing the panel persistence require from $HYPR_LUA ..."
  [ -f "$HYPR_LUA" ] && sed -i '/require("control-panel") -- Omarchy Control Panel scroll persistence/d' "$HYPR_LUA"

  # The panel persists the scroll-patch options into control-panel.lua. On
  # stock Hyprland those are unknown config keys at load time (boot error
  # banner), so strip them; the remaining content is valid stock config.
  # The panel self-gates on the capability probe and will not re-emit them
  # while the patch is absent.
  log "Stripping scroll-patch keys from $PANEL_LUA ..."
  if [ -f "$PANEL_LUA" ]; then
    sed -i '/-- Touchpad scroll acceleration + coast (patched compositor only)/d; /scroll_accel/d; /scroll_decel/d; /scroll_ignore/d' "$PANEL_LUA"
  fi

  # Undo only what WE changed (plugin install / devMode), per the state file.
  local prev_plugin="false" prev_devmode="__ABSENT__"
  if [ -f "$STATE_FILE" ]; then
    prev_plugin=$(python3 -c "import json;d=json.load(open('$STATE_FILE'));print(d.get('pluginInstalledByUs',False))" 2>/dev/null || echo false)
    prev_devmode=$(python3 -c "import json;d=json.load(open('$STATE_FILE'));print(json.dumps(d['prevDevMode']) if 'prevDevMode' in d else '__ABSENT__')" 2>/dev/null || echo "__ABSENT__")
  fi

  if [ "$prev_plugin" = "True" ]; then
    log "Removing the control panel plugin (installed by this script) ..."
    omarchy plugin remove "$PLUGIN_ID" --yes || log "plugin remove failed; remove it manually: omarchy plugin remove $PLUGIN_ID"
  fi

  if [ "$prev_devmode" = "null" ]; then
    log "Removing the devMode key we added (it did not exist before) ..."
    python3 - "$PREFS" <<'PY' || true
import json, os, sys, tempfile
path = sys.argv[1]
if os.path.exists(path):
    try:
        with open(path) as f:
            d = json.load(f)
        if isinstance(d, dict) and "devMode" in d:
            d.pop("devMode", None)
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
            with os.fdopen(fd, "w") as f:
                json.dump(d, f)
            os.replace(tmp, path)
    except Exception:
        pass
PY
  elif [ "$prev_devmode" != "__ABSENT__" ]; then
    log "Restoring previous devMode value ..."
    set_devmode "$prev_devmode" >/dev/null || true
  fi

  rm -f "$STATE_FILE"
  log "Done. Reboot after saving your work to restore the previous session configuration."
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

command -v omarchy >/dev/null 2>&1 || die "the 'omarchy' CLI was not found — this installer is for Omarchy."
command -v python3 >/dev/null 2>&1 || die "python3 is required."

# ---- 1. control panel plugin + bar placement + dev mode ---------------------
log "Fetching the Control Panel at $RELEASE_TAG ..."
mkdir -p "$CACHE_ROOT" "$PANEL_BACKUPS" "$(dirname "$PLUGIN_DIR")"
panel_stage=$(mktemp -d "$(dirname "$PLUGIN_DIR")/.control-panel.XXXXXX")
trap 'rm -rf "$panel_stage"' EXIT
git -C "$panel_stage" init -q
git -C "$panel_stage" remote add origin "$PANEL_REPO"
if [[ $RELEASE_TAG =~ ^[0-9a-fA-F]{40}$ ]]; then
  git -C "$panel_stage" fetch --depth 1 origin "$RELEASE_TAG"
else
  git -C "$panel_stage" fetch --depth 1 origin "refs/tags/$RELEASE_TAG"
fi
panel_sha=$(git -C "$panel_stage" rev-parse FETCH_HEAD^{commit})
PATCH_BASE="https://raw.githubusercontent.com/avillagran/omarchy-control-panel/$panel_sha/patches/hyprland"
PATCH_TAG="pin:$HYPRLAND_PIN series:v3 panel:$panel_sha"
if [[ $RELEASE_TAG =~ ^[0-9a-fA-F]{40}$ && $panel_sha != "${RELEASE_TAG,,}" ]]; then
  die "fetched panel SHA does not match $RELEASE_TAG"
fi
git -C "$panel_stage" checkout -q --detach "$panel_sha"
[[ -f $panel_stage/bin/install-tooltip-patch.sh ]] || die "this panel ref has no tooltip bootstrap"
if grep -q '^OMARCHY_TOOLTIP_COMMIT="OMARCHY_TOOLTIP_COMMIT"$' "$panel_stage/bin/install-tooltip-patch.sh"; then
  die "Omarchy tooltip PR is unpublished: fill OMARCHY_TOOLTIP_COMMIT before installing anything"
fi
if [[ -f $STATE_FILE ]]; then
  original_sha=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("panelSha", ""))' "$STATE_FILE")
  [[ -n $original_sha ]] || die "legacy installation state has no panel SHA or plugin backup; uninstall/review it before replacing the plugin"
  [[ $original_sha == "$panel_sha" ]] || die "existing installation pins $original_sha; refuse moving release $RELEASE_TAG"
fi
plugin_installed_by_us=false
backup_dir=""
if [[ -e $PLUGIN_DIR || -L $PLUGIN_DIR ]]; then
  [[ -d $PLUGIN_DIR && ! -L $PLUGIN_DIR ]] || die "plugin path is not a normal directory: $PLUGIN_DIR"
  if [[ -e $PLUGIN_DIR/.git ]]; then
    [[ -d $PLUGIN_DIR/.git ]] || die "plugin has an external git directory; review manually"
    [[ -z $(git -C "$PLUGIN_DIR" diff --name-only HEAD --) ]] || die "plugin has dirty tracked edits; commit them before installing (no stash performed)"
  fi
  if [[ -f $STATE_FILE ]]; then
    backup_dir=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("pluginBackup", ""))' "$STATE_FILE")
    [[ -z $backup_dir || -d $backup_dir ]] || die "original plugin backup missing: $backup_dir"
    [[ -z $(git -C "$PLUGIN_DIR" status --porcelain) ]] || die "installed plugin changed after installation; refusing replacement"
  else
    backup_dir=$(mktemp -d "$PANEL_BACKUPS/original.XXXXXX")
    rmdir "$backup_dir"
    mv "$PLUGIN_DIR" "$backup_dir"
  fi
else
  plugin_installed_by_us=true
fi
if [[ -f $STATE_FILE ]]; then
  [[ $(git -C "$PLUGIN_DIR" rev-parse HEAD) == "$panel_sha" ]] || die "installed panel revision changed"
  rm -rf "$panel_stage"
else
  if ! mv "$panel_stage" "$PLUGIN_DIR"; then
    [[ -z $backup_dir || ! -d $backup_dir ]] || mv "$backup_dir" "$PLUGIN_DIR"
    die "failed to install panel checkout"
  fi
fi
trap - EXIT
[[ $(git -C "$PLUGIN_DIR" rev-parse HEAD) == "$panel_sha" ]] || die "panel checkout verification failed"

# Record what WE changed for uninstall — but never overwrite an existing
# state file: reruns must preserve the original pre-install values. Write it
# before plugin enable or preferences changes, both of which can fail.
if [ ! -f "$STATE_FILE" ]; then
  mkdir -p "$(dirname "$STATE_FILE")"
  prev_devmode=$(python3 - "$PREFS" <<'PY'
import json, sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text())
    print(json.dumps(data.get('devMode')) if isinstance(data, dict) else 'null')
except (OSError, ValueError):
    print('null')
PY
)
  python3 - "$STATE_FILE" "$plugin_installed_by_us" "$prev_devmode" "$backup_dir" "$panel_sha" <<'PY'
import json, os, sys, tempfile
path, owned, previous, backup, sha = sys.argv[1:]
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, 'w') as out:
    json.dump(dict(pluginInstalledByUs=(owned == 'true'), prevDevMode=json.loads(previous), pluginBackup=backup, panelSha=sha), out)
os.replace(tmp, path)
PY
fi

log "Enabling the bar widget on the RIGHT side ..."
omarchy plugin enable "$PLUGIN_ID" --section right
log "Enabling Dev mode (exposes the Scroll feel card) ..."
set_devmode true >/dev/null

tooltip_state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/tooltip-trial.json"
tooltip_preexisting=false
[[ -f $tooltip_state ]] && tooltip_preexisting=true
# Refuse unpublished Omarchy source before fetching or installing Hyprland.
bash "$PLUGIN_DIR/bin/install-tooltip-patch.sh"
if [[ $tooltip_preexisting == false ]]; then
  python3 - "$STATE_FILE" <<'PY'
import json, os, sys, tempfile
path = sys.argv[1]
with open(path) as source:
    state = json.load(source)
state['tooltipInstalledByUs'] = True
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, 'w') as out:
    json.dump(state, out)
os.replace(tmp, path)
PY
fi

# ---- 2. build dependencies -------------------------------------------------
# Only touch pacman/sudo when something is actually missing: reruns on a
# machine that already built the patch (or Hyprland itself) skip this step
# entirely and never prompt for a password.
if command -v cmake ninja gcc pkgconf hyprwayland-scanner git jq curl >/dev/null 2>&1; then
  log "Build dependencies already present; skipping pacman."
else
  if ! command -v pacman >/dev/null 2>&1; then
    die "patch build currently supports Arch/Omarchy only (pacman not found). Build Hyprland from $HYPRLAND_REPO at $HYPRLAND_PIN with patches/hyprland/ applied, manually."
  fi
  command -v sudo >/dev/null 2>&1 || die "sudo is required to install build dependencies."
  log "Installing build dependencies (pacman) ..."
  sudo pacman -S --needed --noconfirm git cmake ninja gcc pkgconf wayland wayland-protocols hyprwayland-scanner hyprland
fi

# ---- 3. fetch upstream Hyprland at the pinned commit + apply the patch ------
mkdir -p "$PATCH_DIR"
if [ -f "$SRC_DIR/.omarchy-scroll-patch" ] && [ "$(cat "$SRC_DIR/.omarchy-scroll-patch")" = "$PATCH_TAG" ]; then
  log "Patched source already present; skipping fetch/apply."
else
  rm -rf "$SRC_DIR"
  mkdir -p "$SRC_DIR"
  git -C "$SRC_DIR" init -q
  git -C "$SRC_DIR" remote add origin "$HYPRLAND_REPO"
  log "Fetching upstream Hyprland at $HYPRLAND_PIN ..."
  git -C "$SRC_DIR" fetch --depth 1 origin "$HYPRLAND_PIN"
  # Keep the literal full SHA here as well as HYPRLAND_PIN. Besides binding the
  # build to the reviewed source snapshot, this makes the detached checkout
  # independently auditable by the marketplace security baseline.
  git -C "$SRC_DIR" checkout -q --detach 1b85c7aa1b5c41d906880f0f495bcd0749a23175

  log "Downloading scroll patch series ..."
  local_ok=true
  for p in $PATCH_NAMES; do
    # The installed plugin has already been verified at panel_sha. Never read
    # adjacent mutable files from the curl|bash invocation directory.
    if [ -f "$PLUGIN_DIR/patches/hyprland/$p" ]; then
      cp -f "$PLUGIN_DIR/patches/hyprland/$p" "$PATCH_DIR/$p"
    else
      curl -fsSL "$PATCH_BASE/$p" -o "$PATCH_DIR/$p" || local_ok=false
    fi
  done
  [ "$local_ok" = "true" ] || die "failed to download the patch series from $PATCH_BASE"

  log "Applying scroll patch series ..."
  # Apply patch-by-patch (a patch series stacks; a single git apply call with
  # several files does not behave like git am).
  for p in $PATCH_NAMES; do
    if ! git -C "$SRC_DIR" apply --check "$PATCH_DIR/$p"; then
      die "patch $p does not apply to $HYPRLAND_PIN — upstream drifted; refresh HYPRLAND_PIN and patches/hyprland/ together (see README)."
    fi
    git -C "$SRC_DIR" apply "$PATCH_DIR/$p" || die "failed to apply $p"
  done
  printf '%s\n' "$PATCH_TAG" > "$SRC_DIR/.omarchy-scroll-patch"
fi
log "Syncing submodules ..."
git -C "$SRC_DIR" submodule update --init --depth 1

# ---- 4. build (this takes a while) -----------------------------------------
log "Building Hyprland (this can take ~5-15 min on a laptop) ..."
# Bind the execution chain itself to the exact reviewed upstream tree. The
# detached checkout must stay joined to the build with &&: a failed checkout
# must never fall through to compiling a mutable checkout.
git -C "$SRC_DIR" checkout -q --detach 1b85c7aa1b5c41d906880f0f495bcd0749a23175 \
  && cmake -S "$SRC_DIR" -B "$SRC_DIR/build" -DCMAKE_BUILD_TYPE=Release \
  && cmake --build "$SRC_DIR/build" -j"$(nproc)"

# ---- 5. install the shadow binary ------------------------------------------
# mv (not cp) so the swap also works while an older shadow is still running
# (a running executable cannot be opened for writing: ETXTBSY).
log "Installing shadow binary to $SHADOW ..."
install -Dm755 "$SRC_DIR/build/Hyprland" "$SHADOW.new.$$"
shadow_backup=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("shadowBackup", ""))' "$STATE_FILE")
if [[ -f $SHADOW && -z $shadow_backup ]]; then
  mkdir -p "$CACHE_ROOT/shadow-backups"
  shadow_backup=$(mktemp "$CACHE_ROOT/shadow-backups/original.XXXXXX")
  cp -a "$SHADOW" "$shadow_backup"
fi
python3 - "$STATE_FILE" "$shadow_backup" <<'PY'
import json, os, sys, tempfile
path, backup = sys.argv[1:]
with open(path) as source:
    state = json.load(source)
state['shadowOwned'] = True
state['shadowBackup'] = backup
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, 'w') as out:
    json.dump(state, out)
os.replace(tmp, path)
PY
mv -f "$SHADOW.new.$$" "$SHADOW"

# ---- 6. PATH hook (idempotent) ----------------------------------------------
log "Ensuring ~/.local/bin precedes /usr/bin in your login PATH ..."
for profile in "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zprofile"; do
  touch "$profile"
  grep -qF "# ${PATH_MARK}:start" "$profile" && continue
  {
    printf '\n# %s:start (touchpad scroll patch shadow binary)\n' "$PATH_MARK"
    printf 'export PATH="$HOME/.local/bin:$PATH"\n'
    printf '# %s:end\n' "$PATH_MARK"
  } >> "$profile"
done

# ---- 7. gated config block ---------------------------------------------------
# Only applies the new options when the running compositor IS the shadow
# binary, so stock Hyprland (or a system update that removes the shadow)
# never sees unknown config keys.
log "Adding gated scroll options to $INPUT_LUA ..."
mkdir -p "$(dirname "$INPUT_LUA")"
touch "$INPUT_LUA"
sed -i '/-- omarchy-scroll-patch:start/,/-- omarchy-scroll-patch:end/d' "$INPUT_LUA"
cat >> "$INPUT_LUA" <<'LUA'

-- omarchy-scroll-patch:start
-- Touchpad scroll acceleration + coast. Only applied when the RUNNING
-- compositor is the patched shadow binary (~/.local/bin/Hyprland); on stock
-- Hyprland this block is skipped, so no unknown-config-key errors.
do
  local _sf = io.popen("readlink /proc/$PPID/exe 2>/dev/null")
  local _se = _sf and _sf:read("*l") or ""
  if _sf then _sf:close() end
  if _se:match("%.local/bin/Hyprland$") then
    hl.config({ input = { touchpad = {
      scroll_accel_profile = 2,
      scroll_accel_speed = 1.0,
      scroll_accel_max = 3.0,
      scroll_decel = 600,
      scroll_ignore_classes = "google-chrome,chromium,firefox,brave-browser,microsoft-edge,vivaldi,kitty",
    } } })
  end
end
-- omarchy-scroll-patch:end
LUA

# ---- 8. panel persistence wiring ----------------------------------------------
# The panel rewrites ~/.config/hypr/control-panel.lua when you move the Scroll
# feel sliders. Hyprland only reads it if hyprland.lua requires it — wire that
# up here (idempotent) and make sure the file exists so the require never
# errors on a fresh install.
log "Wiring panel scroll persistence into $HYPR_LUA ..."
if [ -f "$HYPR_LUA" ]; then
  if ! grep -qF 'require("control-panel")' "$HYPR_LUA"; then
    printf '\n%s\n' "$REQUIRE_MARK" >> "$HYPR_LUA"
  else
    log "require(\"control-panel\") already present; skipping."
  fi
else
  log "WARNING: $HYPR_LUA not found; panel scroll values will only apply live, not persist across logins."
fi
if [ ! -f "$PANEL_LUA" ]; then
  mkdir -p "$(dirname "$PANEL_LUA")"
  printf -- '-- Written by the Omarchy Control Panel (Scroll feel persistence).\n-- The panel rewrites the hl.config statement below; Hyprland applies it at\n-- startup through the require("control-panel") line in hyprland.lua.\n' > "$PANEL_LUA"
fi

# ---- 9. verify ----------------------------------------------------------------
log "Installed version:"
"$SHADOW" --version | head -1

cat <<'EOF'

[scroll-patch] All done.
[scroll-patch] Reboot after saving your work to activate both trials.
  The compositor binary is chosen at session start, so the patched Hyprland
  only takes effect after a fresh login. Until then the running session is
  still using its previous compositor and tooltip environment.
  Everything else is already in place:
  1. The panel widget is in the TOP-RIGHT of the bar (Dev mode is already on).
  2. After logging back in, open the panel -> Trackpad tab -> "Scroll feel":
     presets, live sliders, "Except browsers and terminals" inertia scope
     and "Config like macOS".

Removal:
  See the pinned uninstall command in README.md.
EOF
