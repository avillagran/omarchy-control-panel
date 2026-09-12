#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
node "$project_dir/tests/model.test.js"
node "$project_dir/tests/manifest.test.js"
node "$project_dir/tests/profile-model.test.js"
node "$project_dir/tests/workspace-model.test.js"
node "$project_dir/tests/backup-model.test.js"
node "$project_dir/tests/backup-connection-ui-model.test.js"
node "$project_dir/tests/panel-startup-safety.test.js"
node "$project_dir/tests/dev-mode.test.js"
node "$project_dir/tests/desktop-helper-paths.test.js"
grep -q 'execDetached(\["bash", root.binPath\])' "$project_dir/BarWidget.qml"
python3 -m unittest discover -s "$project_dir/tests" -p 'test_backup*.py' -v
python3 "$project_dir/tests/test_display_isolation.py"
bash -n "$project_dir/bin/display-manager" "$project_dir/tests/run.sh" "$project_dir/tests/helper.test.sh"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$project_dir"
fi
