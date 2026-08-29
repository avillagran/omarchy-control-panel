#!/usr/bin/env bash
# Wrapper logged for SUPER+W debugging. Logs that the bind fired, then runs the
# real close-tab-or-window.sh. Lets us separate "bind never fires" from "script fails".
LOG=/tmp/superw-bind.log
echo "$(date '+%H:%M:%S') BIND FIRED (wrapper)" >> "$LOG"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/close-tab-or-window.sh" >> "$LOG" 2>&1
echo "$(date '+%H:%M:%S') wrapper exit=$?" >> "$LOG"
