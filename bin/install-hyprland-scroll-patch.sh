#!/usr/bin/env bash
# install-hyprland-scroll-patch.sh
#
# One-liner that installs the Omarchy Control Panel AND lets you try the
# touchpad scroll acceleration + coast patch TODAY, without waiting for the
# upstream PRs to merge:
#
#   curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-control-panel/main/bin/install-hyprland-scroll-patch.sh | bash
#
# What it does:
#   1. Installs the omarchy-control-panel plugin (omarchy plugin add) and
#      enables its bar widget on the RIGHT side (omarchy plugin enable
#      --section right).
#   2. Enables Dev mode in the plugin prefs, which exposes the "Scroll feel"
#      card in Trackpad (presets + live sliders for the patch options).
#   3. Installs build dependencies via pacman (Arch/Omarchy only).
#   4. Clones the fork branch with the patch and builds Hyprland from source
#      (~5-15 min).
#   5. Installs it as a reversible "shadow" binary at ~/.local/bin/Hyprland,
#      which takes precedence over /usr/bin/Hyprland via PATH (pacman updates
#      never touch it).
#   6. Adds a PATH hook to the shell profile files (idempotent).
#   7. Appends a gated block to ~/.config/hypr/input.lua that only applies the
#      new options when the RUNNING compositor is the shadow binary, so stock
#      Hyprland never sees unknown config keys.
#   8. Wires ~/.config/hypr/control-panel.lua (the file the panel rewrites when
#      you move the sliders) into hyprland.lua via require(), so your scroll
#      values survive logout/login.
#
# Removal:
#
#   curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-control-panel/main/bin/install-hyprland-scroll-patch.sh | bash -s -- --uninstall
#
# After installing or uninstalling, log out and back in for the change to take
# effect (the compositor binary is chosen at session start).

set -euo pipefail

PLUGIN_ID="io.github.avillagran.omarchy-control-panel"
PANEL_REPO="https://github.com/avillagran/omarchy-control-panel.git"
REPO_URL="https://github.com/avillagran/Hyprland.git"
BRANCH="feat/touchpad-scroll-acceleration"
SRC_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-control-panel/hyprland-scroll-patch"
SHADOW_DIR="$HOME/.local/bin"
SHADOW="$SHADOW_DIR/Hyprland"
INPUT_LUA="$HOME/.config/hypr/input.lua"
HYPR_LUA="$HOME/.config/hypr/hyprland.lua"
PANEL_LUA="$HOME/.config/hypr/control-panel.lua"
REQUIRE_MARK='require("control-panel") -- Omarchy Control Panel scroll persistence (install-hyprland-scroll-patch.sh)'
PREFS="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/control-panel-prefs.json"
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-control-panel-scroll-patch.json"
PATH_MARK="omarchy-scroll-patch:path"

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
  log "Removing shadow binary $SHADOW ..."
  rm -f "$SHADOW"

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
    rm -f "$STATE_FILE"
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

  log "Done. Log out and back in to return to stock Hyprland."
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

command -v omarchy >/dev/null 2>&1 || die "the 'omarchy' CLI was not found — this installer is for Omarchy."
command -v python3 >/dev/null 2>&1 || die "python3 is required."

# ---- 1. control panel plugin + bar placement + dev mode ---------------------
log "Installing the Omarchy Control Panel plugin ..."
plugin_installed_by_us=false
if ! omarchy plugin list --json 2>/dev/null | grep -q "$PLUGIN_ID"; then
  omarchy plugin add "$PANEL_REPO" --yes
  plugin_installed_by_us=true
else
  log "Plugin already installed; skipping add."
fi

log "Enabling the bar widget on the RIGHT side ..."
omarchy plugin enable "$PLUGIN_ID" --section right

log "Enabling Dev mode (exposes the Scroll feel card) ..."
prev_devmode=$(set_devmode true | sed 's/^prev=//')
[ -z "$prev_devmode" ] && prev_devmode="null"

# Record what WE changed for uninstall — but never overwrite an existing
# state file: reruns must preserve the original pre-install values.
if [ ! -f "$STATE_FILE" ]; then
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '{"pluginInstalledByUs": %s, "prevDevMode": %s}\n' "$plugin_installed_by_us" "$prev_devmode" > "$STATE_FILE"
fi

# ---- 2. build dependencies -------------------------------------------------
if ! command -v pacman >/dev/null 2>&1; then
  die "patch build currently supports Arch/Omarchy only (pacman not found). Build Hyprland from $REPO_URL (branch $BRANCH) manually."
fi
command -v sudo >/dev/null 2>&1 || die "sudo is required to install build dependencies."
log "Installing build dependencies (pacman) ..."
sudo pacman -S --needed --noconfirm git cmake ninja gcc pkgconf wayland wayland-protocols hyprwayland-scanner hyprland

# ---- 3. fetch the patched source -------------------------------------------
log "Fetching $BRANCH from $REPO_URL ..."
mkdir -p "$(dirname "$SRC_DIR")"
if [ -d "$SRC_DIR/.git" ]; then
  git -C "$SRC_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$SRC_DIR" checkout -B "$BRANCH" "origin/$BRANCH"
  git -C "$SRC_DIR" submodule update --init --depth 1
else
  rm -rf "$SRC_DIR"
  git clone --depth 1 --branch "$BRANCH" --recurse-submodules --shallow-submodules "$REPO_URL" "$SRC_DIR"
fi

# ---- 4. build (this takes a while) -----------------------------------------
log "Building Hyprland (this can take ~5-15 min on a laptop) ..."
cmake -S "$SRC_DIR" -B "$SRC_DIR/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$SRC_DIR/build" -j"$(nproc)"

# ---- 5. install the shadow binary ------------------------------------------
# mv (not cp) so the swap also works while an older shadow is still running
# (a running executable cannot be opened for writing: ETXTBSY).
log "Installing shadow binary to $SHADOW ..."
install -Dm755 "$SRC_DIR/build/Hyprland" "$SHADOW.new.$$"
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

[scroll-patch] All done. Next steps:
  1. Log out and back in (the compositor binary is chosen at session start).
  2. The panel widget is in the TOP-RIGHT of the bar (Dev mode is already on).
  3. Open the panel -> Trackpad tab -> "Scroll feel": presets and live sliders.

Removal:
  curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-control-panel/main/bin/install-hyprland-scroll-patch.sh | bash -s -- --uninstall
EOF
