#!/bin/bash

# Whispo Control - Push-to-talk voice recording management
# Press and hold hotkey to record, release to transcribe

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/whispo-transcribe.sh"
STATUS_FILE="/tmp/whispo/status"
PID_FILE="/tmp/whispo/control.pid"

# Check for main script
if [ ! -f "$MAIN_SCRIPT" ]; then
    echo "Error: Main script not found: $MAIN_SCRIPT"
    exit 1
fi

# Make main script executable
chmod +x "$MAIN_SCRIPT"

case "${1:-push}" in
    push)
        # Start recording when key is pressed
        STATUS=$(cat "$STATUS_FILE" 2>/dev/null || echo "IDLE")
        
        if [ "$STATUS" != "RECORDING" ]; then
            "$MAIN_SCRIPT" start &
            echo $! > "$PID_FILE"
        fi
        ;;
        
    release)
        # Stop recording when key is released
        STATUS=$(cat "$STATUS_FILE" 2>/dev/null || echo "IDLE")
        
        if [ "$STATUS" = "RECORDING" ]; then
            "$MAIN_SCRIPT" stop
        else
            # If status is not RECORDING but recording process exists - force stop
            PW_PID=$(pgrep -f "pw-record.*recording.wav")
            if [ -n "$PW_PID" ]; then
                kill -KILL $PW_PID
                rm -f "/tmp/whispo/whispo.pid" "/tmp/whispo/recording.wav"
                echo "IDLE" > "$STATUS_FILE"
            fi
        fi
        
        # Clear PID file
        rm -f "$PID_FILE"
        ;;
        
    toggle)
        # Toggle mode (one press - start, second - stop)
        "$MAIN_SCRIPT" toggle
        ;;
        
    *)
        echo "Usage: $0 {push|release|toggle}"
        echo ""
        echo "  push    - start recording (for push-to-talk)"
        echo "  release - stop recording and transcribe (for push-to-talk)"
        echo "  toggle  - toggle recording (one press)"
        exit 1
        ;;
esac