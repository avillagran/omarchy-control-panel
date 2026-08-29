#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin" "$fixture_dir/state"

cat >"$fixture_dir/monitors.json" <<'JSON'
[
  {"name":"eDP-1","description":"Internal","make":"BOE","model":"Panel","serial":"ABC","disabled":false,"focused":true,"width":1920,"height":1200,"refreshRate":60.001,"x":0,"y":0,"scale":1,"transform":0,"mirrorOf":"none","availableModes":["1920x1200@60.001","1280x800@60"]},
  {"name":"DP-1","description":"Desk","make":"Dell","model":"U2723QE","serial":"XYZ","disabled":false,"focused":false,"width":3840,"height":2160,"refreshRate":60,"x":1920,"y":0,"scale":2,"transform":0,"mirrorOf":"none","availableModes":["3840x2160@60","2560x1440@60"]}
]
JSON

cat >"$fixture_dir/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == -j && ${2:-} == monitors ]]; then
  cat "$TEST_MONITORS"
  exit 0
fi

if [[ ${1:-} == eval ]]; then
  expression=${2:-}
  printf '%s\n' "$expression" >>"$TEST_CALLS"

  if [[ -f $TEST_FAIL_NEXT_EVAL ]]; then
    rm -f "$TEST_FAIL_NEXT_EVAL"
    exit 1
  fi

  if [[ -f $TEST_FAIL_EVAL_AT ]]; then
    fail_at=$(<"$TEST_FAIL_EVAL_AT")
    if (( fail_at <= 1 )); then
      rm -f "$TEST_FAIL_EVAL_AT"
      exit 1
    fi
    printf '%s\n' "$((fail_at - 1))" >"$TEST_FAIL_EVAL_AT"
  fi

  if [[ -f $TEST_IGNORE_EVALS ]]; then
    remaining=$(<"$TEST_IGNORE_EVALS")
    if (( remaining > 0 )); then
      printf '%s\n' "$((remaining - 1))" >"$TEST_IGNORE_EVALS"
      exit 0
    fi
  fi

  [[ $expression =~ output[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]] || exit 1
  name=${BASH_REMATCH[1]}
  tmp="$TEST_MONITORS.tmp"

  if [[ $expression == *"disabled = true"* ]]; then
    jq --arg name "$name" 'map(if .name == $name then .disabled = true else . end)' \
      "$TEST_MONITORS" >"$tmp"
  else
    [[ $expression =~ mode[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]] || exit 1
    mode=${BASH_REMATCH[1]}
    [[ $mode =~ ^([0-9]+)x([0-9]+)@([0-9.]+)$ ]] || exit 1
    width=${BASH_REMATCH[1]}
    height=${BASH_REMATCH[2]}
    refresh=${BASH_REMATCH[3]}
    [[ $expression =~ position[[:space:]]*=[[:space:]]*\"(-?[0-9]+)x(-?[0-9]+)\" ]] || exit 1
    x=${BASH_REMATCH[1]}
    y=${BASH_REMATCH[2]}
    [[ $expression =~ scale[[:space:]]*=[[:space:]]*([0-9.]+) ]] || exit 1
    scale=${BASH_REMATCH[1]}
    [[ $expression =~ transform[[:space:]]*=[[:space:]]*([0-7]) ]] || exit 1
    transform=${BASH_REMATCH[1]}
    mirror=none
    if [[ $expression =~ mirror[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      mirror=${BASH_REMATCH[1]}
    fi
    jq --arg name "$name" --arg mirror "$mirror" \
      --argjson width "$width" --argjson height "$height" --argjson refresh "$refresh" \
      --argjson x "$x" --argjson y "$y" --argjson scale "$scale" --argjson transform "$transform" '
      map(if .name == $name then
        .disabled = false
        | .width = $width | .height = $height | .refreshRate = $refresh
        | .x = $x | .y = $y | .scale = $scale | .transform = $transform
        | .mirrorOf = $mirror
      else . end)' "$TEST_MONITORS" >"$tmp"
  fi
  mv "$tmp" "$TEST_MONITORS"
  exit 0
fi

exit 1
SH

cat >"$fixture_dir/bin/systemd-run" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_SYSTEMD_CALLS"
if [[ -f $TEST_FAIL_NEXT_SYSTEMD_RUN ]]; then
  rm -f "$TEST_FAIL_NEXT_SYSTEMD_RUN"
  exit 1
fi
exit 0
SH

cat >"$fixture_dir/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_SYSTEMCTL_CALLS"
exit 0
SH

chmod +x "$fixture_dir/bin/"*

export PATH="$fixture_dir/bin:$PATH"
export XDG_STATE_HOME="$fixture_dir/state"
export TEST_MONITORS="$fixture_dir/monitors.json"
export TEST_CALLS="$fixture_dir/calls"
export TEST_SYSTEMD_CALLS="$fixture_dir/systemd-calls"
export TEST_SYSTEMCTL_CALLS="$fixture_dir/systemctl-calls"
export TEST_FAIL_NEXT_EVAL="$fixture_dir/fail-next-eval"
export TEST_FAIL_EVAL_AT="$fixture_dir/fail-eval-at"
export TEST_IGNORE_EVALS="$fixture_dir/ignore-evals"
export TEST_FAIL_NEXT_SYSTEMD_RUN="$fixture_dir/fail-next-systemd-run"
export DISPLAY_MANAGER_SETTLE_SECONDS=0
helper="$project_dir/bin/display-manager"

state=$($helper state)
jq -e 'length == 2 and .[0].fingerprint == "BOE|Panel|ABC" and .[1].scale == 2' <<<"$state" >/dev/null
[[ "$($helper topology)" == "BOE|Panel|ABC::Dell|U2723QE|XYZ" ]]

# Real laptops (e.g. Apple) report empty make/model/serial; the fingerprint
# must fall back to the connector name instead of erroring.
jq '[.[] | .make = "" | .model = "" | .serial = ""]' "$TEST_MONITORS" >"$TEST_MONITORS.empty"
cp "$TEST_MONITORS" "$TEST_MONITORS.saved"
mv "$TEST_MONITORS.empty" "$TEST_MONITORS"
empty_state=$($helper state)
jq -e '.[0].fingerprint == "eDP-1" and .[1].fingerprint == "DP-1"' <<<"$empty_state" >/dev/null
mv "$TEST_MONITORS.saved" "$TEST_MONITORS"

[[ $($helper pending | jq -r '.pending') == "false" ]]

# `apply` changes the layout immediately and does NOT arm a rollback timer.
apply_config=$(jq -c '[.[0] + {x:3840}, .[1] + {x:0}]' <<<"$state")
: >"$TEST_SYSTEMD_CALLS"
: >"$TEST_CALLS"
$helper apply "$apply_config" >/dev/null
$helper state | jq -e '.[0].x == 3840 and .[1].x == 0' >/dev/null
if grep -q 'rollback' "$TEST_SYSTEMD_CALLS"; then
  echo "apply must not schedule a rollback" >&2
  exit 1
fi
[[ ! -e $XDG_STATE_HOME/omarchy-control-panel/pending.json ]]
# restore for the following cases
$helper apply "$state" >/dev/null

# Only the changed output is re-configured; identical outputs are skipped so
# the compositor does not tear down panels sitting on them.
: >"$TEST_CALLS"
unchanged=$(jq -c '.[0].y += 10' <<<"$state")
$helper apply "$unchanged" >/dev/null
grep -q 'output = "eDP-1"' "$TEST_CALLS" || { echo "expected eDP-1 to be applied" >&2; exit 1; }
if grep -q 'output = "DP-1"' "$TEST_CALLS"; then
  echo "unchanged DP-1 must not be re-applied" >&2
  exit 1
fi
# A fully identical config is a no-op.
: >"$TEST_CALLS"
$helper apply "$($helper state)" >/dev/null
if grep -q 'hl.monitor' "$TEST_CALLS"; then
  echo "identical config must not touch any output" >&2
  exit 1
fi
$helper apply "$state" >/dev/null

# Scales are auto-corrected to the nearest Hyprland-honoured value before
# applying, so an out-of-range request never reaches the compositor.
clamped=$(jq -c '.[0].scale = 1.85 | .[1].scale = 1.35' <<<"$state")
: >"$TEST_CALLS"
$helper apply "$clamped" >/dev/null
grep -q 'scale = 2' "$TEST_CALLS" || { echo "expected eDP-1 scale clamped to 2" >&2; exit 1; }
grep -q 'scale = 1.3333333333333333' "$TEST_CALLS" || { echo "expected DP-1 scale clamped to 4/3" >&2; exit 1; }
$helper apply "$state" >/dev/null

config=$(jq -c '[.[0] + {x:3840,transform:1,mode:"1920x1200@60.001Hz"}, .[1] + {x:0}]' <<<"$state")
$helper preview "$config" >/dev/null
grep -q '^hl.monitor({ output = "eDP-1", mode = "1920x1200@60.001", position = "3840x0", scale = 1, transform = 1 })$' "$TEST_CALLS"
grep -q 'display-manager rollback$' "$TEST_SYSTEMD_CALLS"
$helper state | jq -e '.[0].x == 3840 and .[0].transform == 1 and .[1].x == 0' >/dev/null
$helper confirm >/dev/null

# Reject an invalid configuration (mirror onto itself, overlapping layouts).
for invalid in \
  '[]' \
  "$(jq -c '.[1].name = .[0].name' <<<"$state")" \
  "$(jq -c '.[1].x = 1000' <<<"$state")" \
  "$(jq -c '.[1].x = 500' <<<"$state")" \
  "$(jq -c '.[0].mirror = .[0].name' <<<"$state")" \
  "$(jq -c '.[0].mirror = "missing"' <<<"$state")"; do
  if $helper preview "$invalid" >/dev/null 2>&1; then
    echo "Expected invalid configuration to fail" >&2
    exit 1
  fi
done

# A position/transform change the compositor rejects must roll back and
# leave no stale pending snapshot.
rejected=$(jq -c '.[0].x += 100 | .[0].transform = 3' <<<"$state")
touch "$TEST_FAIL_NEXT_EVAL"
if $helper preview "$rejected" >/dev/null 2>&1; then
  echo "Expected a rejected position/transform change to roll back" >&2
  exit 1
fi
[[ ! -e $XDG_STATE_HOME/omarchy-control-panel/pending.json ]]

# A compositor command failure must roll back to the snapshot.
touch "$TEST_FAIL_NEXT_EVAL"
if $helper preview "$state" >/dev/null 2>&1; then
  echo "Expected a compositor command failure to roll back" >&2
  exit 1
fi
[[ ! -e $XDG_STATE_HOME/omarchy-control-panel/pending.json ]]

# Mirror then revert restores the original.
state=$($helper state)
mirror_config=$(jq -c '.[0].mirror = .[1].name' <<<"$state")
$helper preview "$mirror_config" >/dev/null
$helper state | jq -e '.[0].mirror == "DP-1"' >/dev/null
$helper revert >/dev/null
$helper state | jq -e '.[0].mirror == ""' >/dev/null

echo "display-manager helper tests passed"
