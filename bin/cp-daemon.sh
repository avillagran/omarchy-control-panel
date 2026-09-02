#!/bin/bash
# Control Panel IPC daemon
# Listens for commands on a Unix socket and launches/kills the desktop panel

SOCKET="/tmp/cp-daemon.sock"
PIDFILE="/tmp/cp-daemon.pid"
LOGFILE="/tmp/cp-daemon.log"

# Cleanup function
cleanup() {
    rm -f "$SOCKET"
    exit 0
}

trap cleanup EXIT INT TERM

# Create socket directory
mkdir -p "$(dirname "$SOCKET")"

# Remove old socket
rm -f "$SOCKET"

echo "CP daemon starting..." > "$LOGFILE"

# Listen for commands using socat or nc
while true; do
    # Use socat to listen on Unix socket
    CMD=$(socat -u UNIX-LISTEN:"$SOCKET" STDOUT 2>/dev/null)
    if [ -n "$CMD" ]; then
        echo "Received command: $CMD" >> "$LOGFILE"
        case "$CMD" in
            toggle)
                # Check if panel is running
                if pgrep -f "quickshell.*control-panel.*shell.qml" > /dev/null 2>&1; then
                    pkill -f "quickshell.*control-panel.*shell.qml"
                    echo "Panel killed" >> "$LOGFILE"
                else
                    DIR="$(cd "$(dirname "$0")/.." && pwd)/desktop"
                    export QML2_IMPORT_PATH="$DIR/qs:/usr/share/omarchy/shell:/usr/lib/qt6/qml"
                    export QML_IMPORT_PATH="$DIR/qs:/usr/share/omarchy/shell:/usr/lib/qt6/qml"
                    cd "$DIR"
                    nohup quickshell -p "$DIR/shell.qml" >> /tmp/cp-desktop.log 2>&1 &
                    echo "Panel launched PID=$!" >> "$LOGFILE"
                fi
                ;;
            open)
                DIR="$(cd "$(dirname "$0")/.." && pwd)/desktop"
                export QML2_IMPORT_PATH="$DIR/qs:/usr/share/omarchy/shell:/usr/lib/qt6/qml"
                cd "$DIR"
                nohup quickshell -p "$DIR/shell.qml" >> /tmp/cp-desktop.log 2>&1 &
                echo "Panel launched PID=$!" >> "$LOGFILE"
                ;;
            close)
                pkill -f "quickshell.*control-panel.*shell.qml"
                echo "Panel killed" >> "$LOGFILE"
                ;;
            *)
                echo "Unknown command: $CMD" >> "$LOGFILE"
                ;;
        esac
    fi
    sleep 0.1
done
