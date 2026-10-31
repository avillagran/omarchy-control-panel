#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
node "$project_dir/tests/model.test.js"
node "$project_dir/tests/manifest.test.js"
node "$project_dir/tests/profile-model.test.js"
node "$project_dir/tests/workspace-model.test.js"
node "$project_dir/tests/pointer-feel-model.test.js"
node "$project_dir/tests/pointer-feel-ui.test.js"
node "$project_dir/tests/precision-circuit.test.js"
node "$project_dir/tests/scroll-feel-model.test.js"
node "$project_dir/tests/scroll-feel-ui.test.js"
node "$project_dir/tests/paths.test.js"
node "$project_dir/tests/backup-model.test.js"
node "$project_dir/tests/backup-connection-ui-model.test.js"
node "$project_dir/tests/panel-startup-safety.test.js"
bash "$project_dir/tests/superw-startup.test.sh"
bash "$project_dir/tests/scroll-feel-startup.test.sh"
node "$project_dir/tests/dev-mode.test.js"
node "$project_dir/tests/task-manager-bundle.test.js"
python3 "$project_dir/tests/run-components-ui.py"
node "$project_dir/tests/desktop-helper-paths.test.js"
node "$project_dir/tests/tooltip-ui.test.js"
python3 "$project_dir/tests/test_tooltip_settings.py"
python3 "$project_dir/tests/test_installers_tooltips.py"
grep -q 'execDetached(\["bash", root.binPath\])' "$project_dir/BarWidget.qml"
node "$project_dir/tests/mission-control-and-indicators.test.js"
python3 -m unittest "$project_dir/tests/test_workspace_widget_installer.py" "$project_dir/tests/test_display_hotplug_sync.py"
python3 -m unittest discover -s "$project_dir/tests" -p 'test_backup*.py' -v
python3 "$project_dir/tests/test_display_isolation.py"
bash -n "$project_dir/bin/apply-device-rules" "$project_dir/bin/display-manager" "$project_dir/bin/apply-superw-bind" "$project_dir/bin/install-hyprland-scroll-patch.sh" "$project_dir/tests/run.sh" "$project_dir/tests/helper.test.sh" "$project_dir/tests/superw-startup.test.sh"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$project_dir"
fi
# Qt 6.12's QtQuick Color singleton shadows qs.Commons Color: pin QtQuick.
if grep -rnE --include=*.qml '^import QtQuick(\.Window)?( as [A-Za-z]+)?$' "$project_dir" --exclude-dir=sketches --exclude-dir=.git; then
  echo "unversioned QtQuick import: use 'import QtQuick 6.11'" >&2
  exit 1
fi
