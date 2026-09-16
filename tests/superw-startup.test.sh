#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.local/state/omarchy"
export CAPTURE="$tmp/eval.lua"
export BIND_MODE=missing

cat > "$tmp/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == binds ]]; then
  if [[ ${BIND_MODE:-missing} == pair ]]; then
    printf '%s\n' '[{"key":"W","modmask":64,"release":false,"non_consuming":false,"dispatcher":"function: 0x1"},{"key":"W","modmask":64,"release":true,"non_consuming":false,"dispatcher":"function: 0x2"}]'
  else
    printf '%s\n' '[]'
  fi
  exit 0
fi
if [[ ${1:-} == eval ]]; then
  printf '%s' "${2:-}" > "$CAPTURE"
  printf '%s\n' ok
  exit 0
fi
exit 2
SH
chmod +x "$tmp/bin/hyprctl"

printf '%s\n' '{"browserCloseTab":false}' > "$tmp/home/.local/state/omarchy/control-panel-prefs.json"
PATH="$tmp/bin:$PATH" HOME="$tmp/home" bash "$project_dir/bin/apply-superw-bind"
grep -q 'if isBrowser and false then' "$CAPTURE"
grep -q 'hl.bind("SUPER + W", function() end)' "$CAPTURE"
grep -q '{ release = true }' "$CAPTURE"

PATH="$tmp/bin:$PATH" HOME="$tmp/home" bash "$project_dir/bin/apply-superw-bind" true
grep -q 'if isBrowser and true then' "$CAPTURE"

rm -f "$CAPTURE"
BIND_MODE=pair PATH="$tmp/bin:$PATH" HOME="$tmp/home" bash "$project_dir/bin/apply-superw-bind"
test ! -e "$CAPTURE"

printf '%s\n' 'SUPER+W startup binding tests passed'
