#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
node "$project_dir/tests/model.test.js"
node "$project_dir/tests/manifest.test.js"
"$project_dir/tests/helper.test.sh"
bash -n "$project_dir/bin/display-manager" "$project_dir/tests/run.sh" "$project_dir/tests/helper.test.sh"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$project_dir"
fi
