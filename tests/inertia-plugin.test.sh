#!/usr/bin/env bash
# bin/inertia-plugin against stubbed hyprctl/make/pkg-config. No real compositor.
# The temp dir is left in place on purpose: tests never delete file trees.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$project_dir/bin/inertia-plugin"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/inertia-plugin-test.XXXXXX")
commit=11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947
mkdir -p "$tmp/bin" "$tmp/home/.local/state/omarchy"
export HOME="$tmp/home" XDG_STATE_HOME="$tmp/home/.local/state" PATH="$tmp/bin:$PATH"
export FAKE="$tmp" HYPRLAND_VERSION_HEADER="$tmp/version.h" OMARCHY_INERTIA_SO="$tmp/absent/inertia.so"
printf '#define GIT_COMMIT_HASH    "%s"\n' "$commit" > "$HYPRLAND_VERSION_HEADER"
printf '%s\n' "$commit" > "$tmp/running"

cat > "$tmp/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$1 ${2:-}" in
  "version -j") printf '{"commit":"%s"}\n' "$(cat "$FAKE/running")" ;;
  "plugin list") if [[ -f $FAKE/loaded ]]; then echo '[{"name":"omarchy-inertia"}]'; else echo '[]'; fi ;;
  "plugin load") [[ -f $FAKE/refuse ]] && { echo "error"; exit 0; }; echo "$3" > "$FAKE/loaded"; echo ok ;;
  "plugin unload") [[ $(cat "$FAKE/loaded" 2>/dev/null) == "$3" ]] && rm -f "$FAKE/loaded"; echo ok ;;
esac
STUB
cat > "$tmp/bin/make" <<'STUB'
#!/usr/bin/env bash
echo "make $*" >> "$FAKE/calls"
[[ -f $FAKE/makefail ]] && { echo "boom" >&2; exit 1; }
for a in "$@"; do [[ $a == OUT=* ]] && echo elf > "${a#OUT=}"; done
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/pkg-config"
chmod +x "$tmp/bin/"*
prefs="$HOME/.local/state/omarchy/control-panel-prefs.json"
builds() { grep -c '^make ' "$tmp/calls" || true; }
fail() { echo "FAIL: $*" >&2; exit 1; }

bash "$helper" sync
[[ ! -f $tmp/loaded ]] || fail "sync without prefs must not load"

echo '{"inertia": true}' > "$prefs"
bash "$helper" sync
[[ -f $tmp/loaded ]] || fail "sync with inertia=true must load"
[[ $(cat "$tmp/loaded") == "$XDG_STATE_HOME/omarchy/control-panel-inertia/build/$commit-"*"/control-panel-inertia.so" ]] || fail "build must live in the state dir, keyed by the Hyprland commit"
[[ $(builds) == 1 ]] || fail "first load builds once"
bash "$helper" on
[[ $(builds) == 1 ]] || fail "loaded + cached must not rebuild"
[[ $(grep -c '^plugin load' "$tmp/calls") == 1 ]] || fail "already loaded must not load twice"
[[ $(bash "$helper" status) == loaded ]] || fail "status loaded"

bash "$helper" off
[[ ! -f $tmp/loaded ]] || fail "off must unload"
bash "$helper" on
[[ $(builds) == 1 ]] || fail "reload after off uses the cached build"

echo '{"inertia": false, "inertiaMouse": true}' > "$prefs"
bash "$helper" sync
[[ -f $tmp/loaded ]] || fail "sync with only mouse-wheel inertia keeps the plugin loaded"

echo '{"inertia": false}' > "$prefs"
bash "$helper" sync
[[ ! -f $tmp/loaded ]] || fail "sync with inertia=false must unload"

# Hyprland package updated but the session still runs the old compositor.
printf '#define GIT_COMMIT_HASH    "%s"\n' 0000000000000000000000000000000000000000 > "$HYPRLAND_VERSION_HEADER"
if bash "$helper" on 2>"$tmp/err"; then fail "mismatched headers must not load"; fi
grep -q 'next login' "$tmp/err" || fail "mismatch explains it waits for next login"
[[ ! -f $tmp/loaded ]] || fail "mismatch must not load"
[[ $(builds) == 1 ]] || fail "mismatch must not build"

# After relogin: new commit, build failure is remembered instead of retried.
new=1111111111111111111111111111111111111111
printf '#define GIT_COMMIT_HASH    "%s"\n' "$new" > "$HYPRLAND_VERSION_HEADER"
printf '%s\n' "$new" > "$tmp/running"
touch "$tmp/makefail"
if bash "$helper" on 2>/dev/null; then fail "failed build must report failure"; fi
if bash "$helper" on 2>/dev/null; then fail "failed build must keep failing"; fi
[[ $(builds) == 2 ]] || fail "a failed build is not retried for the same Hyprland"
rm -f "$tmp/makefail"

# Compositor refuses the library (ABI check in PLUGIN_INIT).
rm -f "$XDG_STATE_HOME/omarchy/control-panel-inertia/build/$new-"*.failed
touch "$tmp/refuse"
if bash "$helper" on 2>"$tmp/err"; then fail "refused load must fail"; fi
grep -q 'refused' "$tmp/err" || fail "refusal is reported"
[[ ! -f $XDG_STATE_HOME/omarchy/control-panel-inertia/loaded ]] || fail "refused load must not be recorded"
! compgen -G "$XDG_STATE_HOME/omarchy/control-panel-inertia/build/$commit-*/control-panel-inertia.so" >/dev/null || fail "old builds are pruned"

# Omarchy's package is installed: load it instead of building our own.
rm -f "$tmp/refuse"
bash "$helper" off
mkdir -p "$tmp/system" && echo elf > "$tmp/system/inertia.so"
before=$(builds)
OMARCHY_INERTIA_SO="$tmp/system/inertia.so" bash "$helper" on
[[ $(cat "$tmp/loaded") == "$tmp/system/inertia.so" ]] || fail "the Omarchy package is preferred"
[[ $(builds) == "$before" ]] || fail "no build when the Omarchy package is installed"
OMARCHY_INERTIA_SO="$tmp/system/inertia.so" bash "$helper" off
[[ ! -f $tmp/loaded ]] || fail "off unloads the Omarchy package too"

# Omarchy's config loaded it (no record of ours): leave it alone both ways.
echo "/usr/lib/omarchy-hyprland-inertia/inertia.so" > "$tmp/loaded"
loads=$(grep -c '^plugin load' "$tmp/calls")
bash "$helper" on
[[ $(grep -c '^plugin load' "$tmp/calls") == "$loads" ]] || fail "on does not load twice over Omarchy's"
bash "$helper" off 2>/dev/null
[[ -f $tmp/loaded ]] || fail "off leaves Omarchy's plugin loaded"
rm -f "$tmp/loaded"

echo "inertia-plugin helper checks passed"
