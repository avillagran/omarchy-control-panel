#!/usr/bin/env bash
# bin/inertia-watch against a stubbed inertia-plugin and notify-send.
# The temp dir is left in place on purpose: tests never delete file trees.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/inertia-watch-test.XXXXXX")
mkdir -p "$tmp/plugin/bin" "$tmp/plugin/desktop" "$tmp/stubs" "$tmp/state"
cp "$project_dir/bin/inertia-watch" "$tmp/plugin/bin/"
cp "$project_dir/desktop/i18n.json" "$tmp/plugin/desktop/"
export FAKE="$tmp" XDG_STATE_HOME="$tmp/state" PATH="$tmp/stubs:$PATH" LANG=es_CL.UTF-8
export HYPRLAND_INSTANCE_SIGNATURE=session-a

cat > "$tmp/plugin/bin/inertia-plugin" <<'STUB'
#!/usr/bin/env bash
echo "plugin $1" >> "$FAKE/calls"
case $1 in
  check) cat "$FAKE/check" ;;
  on) [[ -f $FAKE/onfail ]] && { echo "missing c++" >&2; exit 1; }; printf 'ok\n' > "$FAKE/check" ;;
esac
STUB
cat > "$tmp/stubs/notify-send" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE/notes"
for a in "$@"; do [[ $a == reinstall=* ]] && cat "$FAKE/answer" 2>/dev/null; done
exit 0
STUB
chmod +x "$tmp/plugin/bin/"* "$tmp/stubs/"*
watch() { bash "$tmp/plugin/bin/inertia-watch"; }
notes() { [[ -f $tmp/notes ]] && wc -l < "$tmp/notes" || echo 0; }
fail() { echo "FAIL: $*" >&2; exit 1; }

printf 'ok\n' > "$tmp/check"
watch
grep -q '^plugin sync' "$tmp/calls" || fail "watch runs sync first"
[[ $(notes) == 0 ]] || fail "no notification while inertia is loaded"

printf 'off\n' > "$tmp/check"
watch
[[ $(notes) == 0 ]] || fail "no notification when inertia is off"

# Wanted but missing: offer a reinstall, in the session language.
printf 'missing\tbuild failed; see x\n' > "$tmp/check"
echo reinstall > "$tmp/answer"
watch
grep -q 'reinstall=Reinstalar inercia' "$tmp/notes" || fail "offers a localized reinstall button"
grep -q 'build failed' "$tmp/notes" || fail "shows the reason"
grep -q '^plugin on' "$tmp/calls" || fail "the button reinstalls"
grep -q 'La inercia volvió a funcionar' "$tmp/notes" || fail "confirms the reinstall"

# Once per Hyprland session.
printf 'missing\tbuild failed\n' > "$tmp/check"
before=$(notes)
watch
[[ $(notes) == "$before" ]] || fail "one notification per session"

# New session, reinstall fails: say so with the error.
export HYPRLAND_INSTANCE_SIGNATURE=session-b
touch "$tmp/onfail"
watch
grep -q -- '-u critical -- No se pudo reinstalar la inercia missing c++' "$tmp/notes" || fail "reports a failed reinstall"

# Updated but not restarted: no button, just say it comes back after login.
export HYPRLAND_INSTANCE_SIGNATURE=session-c
printf 'missing\tHyprland was updated; inertia resumes after the next login\n' > "$tmp/check"
before=$(grep -c reinstall= "$tmp/notes")
watch
[[ $(grep -c reinstall= "$tmp/notes") == "$before" ]] || fail "no reinstall button while waiting for login"
grep -q 'próximo inicio de sesión' "$tmp/notes" || fail "explains it returns after login"

echo "inertia-watch checks passed"
