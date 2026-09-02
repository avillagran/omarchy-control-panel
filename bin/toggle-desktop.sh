#!/bin/bash
# Toggle desktop Control Panel
DIR="/home/avillagran/.config/omarchy/plugins/io.github.avillagran.omarchy-control-panel/desktop"

if pgrep -f "quickshell.*control-panel.*shell.qml" > /dev/null 2>&1; then
    pkill -f "quickshell.*control-panel.*shell.qml"
else
    cd "$DIR"
    export QML2_IMPORT_PATH="$DIR/qs:/usr/share/omarchy/shell:/usr/lib/qt6/qml"
    export QML_IMPORT_PATH="$DIR/qs:/usr/share/omarchy/shell:/usr/lib/qt6/qml"
    nohup quickshell -p "$DIR/shell.qml" > /tmp/cp-desktop.log 2>&1 &
fi
