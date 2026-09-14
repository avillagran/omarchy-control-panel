#!/usr/bin/env bash
# install-hyprland-scroll-patch.sh
#
# One-liner installer that lets anyone try the touchpad scroll acceleration +
# coast patch TODAY, without waiting for the upstream PRs to merge:
#
#   curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-control-panel/main/bin/install-hyprland-scroll-patch.sh | bash
#
# What it does (no root for the patch itself):
#   1. Installs build dependencies via pacman (Arch/Omarchy only).
#   2. Clones the fork branch with the patch and builds Hyprland from source.
#   3. Installs it as a "shadow" binary at ~/.local/bin/Hyprland, which takes
#      precedence over /usr/bin/Hyprland via PATH (reversible, no pacman
#      conflicts — pacman updates never touch it).
#   4. Adds a PATH hook to the shell profile files (idempotent).
#   5. Appends a gated block to ~/.config/hypr/input.lua that only applies the
#      new options when the RUNNING compositor is the shadow binary, so stock
#      Hyprland never sees unknown config keys.
#
# Removal:
#
#   curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-control-panel/main/bin/install-hyprland-scroll-patch.sh | bash -s -- --uninstall
#
# After installing or uninstalling, log out and back in for the change to take
# effect (the compositor binary is chosen at session start).

set -euo pipefail

REPO_URL="https://github.com/avillagran/Hyprland.git"
BRANCH="feat/touchpad-scroll-acceleration"
SRC_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-control-panel/hyprland-scroll-patch"
SHADOW_DIR="$HOME/.local/bin"
SHADOW="$SHADOW_DIR/Hyprland"
INPUT_LUA="$HOME/.config/hypr/input.lua"
PATH_MARK="omarchy-scroll-patch:path"

log() { printf '\033[1;36m[scroll-patch]\033[0m %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

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

  log "Done. Log out and back in to return to stock Hyprland."
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

# ---- 1. build dependencies -------------------------------------------------
if ! command -v pacman >/dev/null 2>&1; then
  die "this installer currently supports Arch/Omarchy only (pacman not found). Build Hyprland from $REPO_URL (branch $BRANCH) manually."
fi
command -v sudo >/dev/null 2>&1 || die "sudo is required to install build dependencies."
log "Installing build dependencies (pacman) ..."
sudo pacman -S --needed --noconfirm git cmake ninja gcc pkgconf wayland wayland-protocols hyprwayland-scanner hyprland

# ---- 2. fetch the patched source -------------------------------------------
log "Fetching $BRANCH from $REPO_URL ..."
mkdir -p "$(dirname "$SRC_DIR")"
if [ -d "$SRC_DIR/.git" ]; then
  git -C "$SRC_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$SRC_DIR" checkout -B "$BRANCH" "origin/$BRANCH"
else
  rm -rf "$SRC_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$SRC_DIR"
fi

# ---- 3. build (this takes a while) -----------------------------------------
log "Building Hyprland (this can take ~5-15 min on a laptop) ..."
cmake -S "$SRC_DIR" -B "$SRC_DIR/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$SRC_DIR/build" -j"$(nproc)"

# ---- 4. install the shadow binary ------------------------------------------
# mv (not cp) so the swap also works while an older shadow is still running
# (a running executable cannot be opened for writing: ETXTBSY).
log "Installing shadow binary to $SHADOW ..."
install -Dm755 "$SRC_DIR/build/Hyprland" "$SHADOW.new.$$"
mv -f "$SHADOW.new.$$" "$SHADOW"

# ---- 5. PATH hook (idempotent) ----------------------------------------------
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

# ---- 6. gated config block ---------------------------------------------------
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
      scroll_ignore_classes = "google-chrome,chromium,firefox,brave-browser,microsoft-edge,vivaldi",
    } } })
  end
end
-- omarchy-scroll-patch:end
LUA

# ---- 7. verify ----------------------------------------------------------------
log "Installed version:"
"$SHADOW" --version | head -1

cat <<'EOF'

[scroll-patch] All done. Next steps:
  1. Log out and back in (the compositor binary is chosen at session start).
  2. Open the Omarchy Control Panel -> Profiles -> enable "Dev mode".
  3. Trackpad tab -> "Scroll feel": presets and live sliders.

Removal:
  curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-control-panel/main/bin/install-hyprland-scroll-patch.sh | bash -s -- --uninstall
EOF
