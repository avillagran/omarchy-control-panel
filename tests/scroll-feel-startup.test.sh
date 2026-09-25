#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.local/state/omarchy"
export CAPTURE="$tmp/eval.lua"
export LIVE_MODE=defaults
export XDG_RUNTIME_DIR="$tmp/runtime"
mkdir -p "$XDG_RUNTIME_DIR"

cat > "$tmp/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == getoption ]]; then
  if [[ ${LIVE_MODE:-defaults} == unsupported ]]; then
    exit 2
  fi
  if [[ ${LIVE_MODE:-defaults} == hung ]]; then
    sleep 5
    exit 2
  fi
  key=${2:-}
  case "$key" in
    input:touchpad:scroll_accel_profile|input:mouse:scroll_accel_profile)
      value=0; [[ ${LIVE_MODE:-defaults} == configured ]] && value=2
      printf '{"option":"%s","int":%s,"set":true}\n' "$key" "$value"
      ;;
    input:touchpad:scroll_accel_speed|input:mouse:scroll_accel_speed)
      value=1.0; [[ ${LIVE_MODE:-defaults} == configured ]] && value=1.3
      printf '{"option":"%s","float":%s,"set":true}\n' "$key" "$value"
      ;;
    input:touchpad:scroll_accel_max|input:mouse:scroll_accel_max)
      value=3.0; [[ ${LIVE_MODE:-defaults} == configured ]] && value=4.0
      printf '{"option":"%s","float":%s,"set":true}\n' "$key" "$value"
      ;;
    input:touchpad:scroll_decel|input:mouse:scroll_decel)
      value=600; [[ ${LIVE_MODE:-defaults} == configured ]] && value=1000
      printf '{"option":"%s","int":%s,"set":true}\n' "$key" "$value"
      ;;
    input:touchpad:scroll_ignore_classes)
      value=''; [[ ${LIVE_MODE:-defaults} == configured ]] && value='google-chrome,chromium,firefox,brave-browser,microsoft-edge,vivaldi,kitty'
      printf '{"option":"%s","str":"%s","set":true}\n' "$key" "$value"
      ;;
    *) exit 2 ;;
  esac
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

cat > "$tmp/home/.local/state/omarchy/control-panel-prefs.json" <<'JSON'
{
  "scrollFeelConfigured": true,
  "scrollIgnoreMode": "browsers",
  "scrollAccelProfile": 2,
  "scrollAccelSpeed": 1.3,
  "scrollAccelMax": 4.0,
  "scrollDecel": 1000,
  "mouseScrollFeelEnabled": true
}
JSON

PATH="$tmp/bin:$PATH" HOME="$tmp/home" bash "$project_dir/bin/apply-scroll-feel"
grep -q 'input = { touchpad = {' "$CAPTURE"
grep -q 'scroll_accel_profile = 2' "$CAPTURE"
grep -q 'scroll_accel_speed = 1.30' "$CAPTURE"
grep -q 'scroll_accel_max = 4.00' "$CAPTURE"
grep -q 'scroll_decel = 1000' "$CAPTURE"
grep -q 'scroll_ignore_classes = "google-chrome,chromium,firefox,brave-browser,microsoft-edge,vivaldi,kitty"' "$CAPTURE"
grep -q 'input = { mouse = {' "$CAPTURE"

rm -f "$CAPTURE"
LIVE_MODE=configured PATH="$tmp/bin:$PATH" HOME="$tmp/home" bash "$project_dir/bin/apply-scroll-feel"
test ! -e "$CAPTURE"

start=$SECONDS
LIVE_MODE=unsupported PATH="$tmp/bin:$PATH" HOME="$tmp/home" bash "$project_dir/bin/apply-scroll-feel"
test $((SECONDS - start)) -lt 2
test ! -e "$CAPTURE"

start=$SECONDS
LIVE_MODE=hung PATH="$tmp/bin:$PATH" HOME="$tmp/home" bash "$project_dir/bin/apply-scroll-feel"
test $((SECONDS - start)) -lt 3
test ! -e "$CAPTURE"

exec 9>"$XDG_RUNTIME_DIR/omarchy-control-panel-scroll-feel.lock"
flock -n 9
start=$SECONDS
LIVE_MODE=hung PATH="$tmp/bin:$PATH" HOME="$tmp/home" bash "$project_dir/bin/apply-scroll-feel"
test $((SECONDS - start)) -lt 2
exec 9>&-

printf '%s\n' 'Scroll-feel startup persistence tests passed'
