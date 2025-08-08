#!/bin/bash

# Whispo - Whisper Voice-to-Text for Linux
# Записывает аудио с микрофона, распознает через Whisper и вставляет текст

# Настройки
TEMP_DIR="/tmp/whispo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIO_FILE="$TEMP_DIR/recording.wav"
PID_FILE="$TEMP_DIR/whispo.pid"
STATUS_FILE="$TEMP_DIR/status"
WHISPER_MODEL="small"  # tiny, base, small, medium, large
LANGUAGE="auto"  # Language for recognition (auto-detect)

# Создаем временную директорию
mkdir -p "$TEMP_DIR"

# Функция для записи аудио
record_audio() {
    echo "RECORDING" > "$STATUS_FILE"
    
    # Notification about recording start
    notify-send "Whispo" "🎤 Recording started..." -t 2000
    
    # Recording from microphone via pw-record (PipeWire)
    # Using correct format for pw-record
    pw-record --format=s16 --channels=1 --rate=16000 "$AUDIO_FILE" &
    RECORD_PID=$!
    echo $RECORD_PID > "$PID_FILE"
    
    # Ждем пока запись идет
    wait $RECORD_PID
}

# Function to stop recording
stop_recording() {
    local stopped=0
    
    echo "Attempting to stop recording..." >&2
    
    # Check PID file first
    if [ -f "$PID_FILE" ]; then
        RECORD_PID=$(cat "$PID_FILE")
        echo "Found PID file with PID: $RECORD_PID" >&2
        
        if kill -0 $RECORD_PID 2>/dev/null; then
            echo "Process $RECORD_PID is running, stopping..." >&2
            kill -TERM $RECORD_PID
            sleep 0.5
            # Если процесс все еще жив, убиваем принудительно
            if kill -0 $RECORD_PID 2>/dev/null; then
                echo "Process still alive, force killing..." >&2
                kill -KILL $RECORD_PID
                sleep 0.2
            fi
            rm -f "$PID_FILE"
            echo "STOPPED" > "$STATUS_FILE"
            stopped=1
        else
            echo "PID $RECORD_PID is not running, cleaning up..." >&2
            rm -f "$PID_FILE"
        fi
    else
        echo "No PID file found" >&2
    fi
    
    # If no PID file, try to find pw-record process
    PW_PID=$(pgrep -f "pw-record.*recording.wav")
    if [ -n "$PW_PID" ]; then
        echo "Found pw-record process: $PW_PID, stopping..." >&2
        kill -TERM $PW_PID
        sleep 0.5
        if kill -0 $PW_PID 2>/dev/null; then
            echo "Force killing pw-record process..." >&2
            kill -KILL $PW_PID
            sleep 0.2
        fi
        echo "STOPPED" > "$STATUS_FILE"
        stopped=1
    else
        echo "No pw-record process found" >&2
    fi
    
    # Check if we have an audio file - if yes, consider recording stopped successfully
    if [ -f "$AUDIO_FILE" ]; then
        AUDIO_SIZE=$(stat -c%s "$AUDIO_FILE" 2>/dev/null || echo "0")
        echo "Audio file exists with size: $AUDIO_SIZE bytes" >&2
        if [ "$AUDIO_SIZE" -gt 0 ]; then
            echo "STOPPED" > "$STATUS_FILE"
            stopped=1
        fi
    else
        echo "No audio file found: $AUDIO_FILE" >&2
    fi
    
    if [ $stopped -eq 1 ]; then
        echo "Recording stopped successfully" >&2
        return 0
    else
        echo "No recording was active" >&2
        # Set status to IDLE anyway
        echo "IDLE" > "$STATUS_FILE"
        return 1
    fi
}

# Function for transcription
transcribe() {
    source "$SCRIPT_DIR/venv/bin/activate"
    echo "TRANSCRIBING" > "$STATUS_FILE"
    
    # Notification about transcription start
    notify-send "Whispo" "⚙️ Transcribing speech..." -t 2000
    
    # Check if audio file exists
    if [ ! -f "$AUDIO_FILE" ]; then
        echo "Error: Audio file not found: $AUDIO_FILE" >&2
        deactivate
        return 1
    fi
    
    # Check audio file size
    AUDIO_SIZE=$(stat -c%s "$AUDIO_FILE" 2>/dev/null || echo "0")
    if [ "$AUDIO_SIZE" -lt 1000 ]; then
        echo "Warning: Audio file is too small ($AUDIO_SIZE bytes)" >&2
        deactivate
        return 1
    fi
    
    # Transcription via whisper - redirect all output to stderr except final result
    local whisper_args=(
        --model "$WHISPER_MODEL"
        --output_format txt
        --output_dir "$TEMP_DIR"
        --fp16 False
        --verbose False
    )
    
    # Add language parameter only if not auto
    if [ "$LANGUAGE" != "auto" ]; then
        whisper_args+=(--language "$LANGUAGE")
    fi
    
    echo "Running whisper with args: ${whisper_args[@]}" >&2
    whisper "$AUDIO_FILE" "${whisper_args[@]}" >/dev/null 2>&1
    
    local TEXT=""
    # Read result from file
    if [ -f "$TEMP_DIR/recording.txt" ]; then
        TEXT=$(cat "$TEMP_DIR/recording.txt" | tr -d '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        rm -f "$TEMP_DIR/recording.txt"
        echo "Transcribed text: '$TEXT'" >&2
    else
        echo "Error: Transcription file not found: $TEMP_DIR/recording.txt" >&2
        deactivate
        return 1
    fi
    
    echo "$TEXT"
    deactivate
}

# Function to insert text
insert_text() {
    local text="$1"
    
    if [ -z "$text" ]; then
        notify-send "Whispo" "❌ No text recognized" -t 2000
        return 1
    fi
    
    # Добавляем небольшую задержку для активации окна
    sleep 0.2
    
    # Text insertion via wtype (for Wayland) or xdotool (for X11)
    if [ -n "$WAYLAND_DISPLAY" ]; then
        # For Wayland use wtype with delay
        echo "Inserting text (Wayland): $text" >&2
        wtype "$text"
        WTYPE_EXIT_CODE=$?
        if [ $WTYPE_EXIT_CODE -ne 0 ]; then
            notify-send "Whispo" "❌ Failed to insert text (wtype error: $WTYPE_EXIT_CODE)" -t 3000
            return 1
        fi
    else
        # For X11 use xdotool
        echo "Inserting text (X11): $text" >&2
        xdotool type "$text"
        XDOTOOL_EXIT_CODE=$?
        if [ $XDOTOOL_EXIT_CODE -ne 0 ]; then
            notify-send "Whispo" "❌ Failed to insert text (xdotool error: $XDOTOOL_EXIT_CODE)" -t 3000
            return 1
        fi
    fi
    
    # Success notification
    notify-send "Whispo" "✅ Text inserted: ${text:0:50}..." -t 2000
}

# Main logic
case "${1:-start}" in
    start)
        # Проверяем, не запущена ли уже запись
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if kill -0 $PID 2>/dev/null; then
                echo "Запись уже идет (PID: $PID)"
                exit 1
            fi
        fi
        
        # Дополнительная проверка на зависшие процессы
        PW_PID=$(pgrep -f "pw-record.*recording.wav")
        if [ -n "$PW_PID" ]; then
            echo "Обнаружен зависший процесс записи, очищаем..."
            kill -KILL $PW_PID
            rm -f "$PID_FILE" "$AUDIO_FILE"
            echo "IDLE" > "$STATUS_FILE"
        fi
        
        # Запускаем запись в фоне
        record_audio
        ;;
        
    stop)
        # Stop recording and process
        echo "Stopping recording..." >&2
        
        # Try to stop recording (this now provides detailed logs)
        if stop_recording 2>&1; then
            # Check if we have an audio file to process
            if [ -f "$AUDIO_FILE" ]; then
                AUDIO_SIZE=$(stat -c%s "$AUDIO_FILE" 2>/dev/null || echo "0")
                echo "Processing audio file (size: $AUDIO_SIZE bytes)..." >&2
                
                if [ "$AUDIO_SIZE" -lt 1000 ]; then
                    echo "Audio file too small, skipping transcription" >&2
                    notify-send "Whispo" "❌ Recording too short" -t 3000
                    rm -f "$AUDIO_FILE"
                    echo "IDLE" > "$STATUS_FILE"
                    exit 1
                fi
                
                # Transcribe
                echo "Starting transcription..." >&2
                TEXT=$(transcribe)
                TRANSCRIBE_EXIT_CODE=$?
                
                if [ $TRANSCRIBE_EXIT_CODE -ne 0 ]; then
                    echo "Transcription failed with exit code: $TRANSCRIBE_EXIT_CODE" >&2
                    notify-send "Whispo" "❌ Transcription failed" -t 3000
                    rm -f "$AUDIO_FILE"
                    echo "IDLE" > "$STATUS_FILE"
                    exit 1
                fi
                
                # Insert text
                if [ -n "$TEXT" ] && [ "$TEXT" != "" ]; then
                    echo "Inserting text: '$TEXT'" >&2
                    if insert_text "$TEXT"; then
                        echo "✅ Successfully recognized and inserted: $TEXT" >&2
                    else
                        echo "❌ Failed to insert text: $TEXT" >&2
                        notify-send "Whispo" "❌ Failed to insert text" -t 3000
                    fi
                else
                    echo "❌ No text recognized or empty result" >&2
                    notify-send "Whispo" "❌ No text recognized" -t 3000
                fi
            else
                echo "❌ No audio file found after stopping recording" >&2
                notify-send "Whispo" "❌ No recording found" -t 3000
            fi
            
            # Cleanup
            rm -f "$AUDIO_FILE"
            echo "IDLE" > "$STATUS_FILE"
        else
            # stop_recording failed, but let's check if there's still an audio file
            echo "Stop recording returned error, but checking for audio file..." >&2
            if [ -f "$AUDIO_FILE" ]; then
                echo "Audio file exists despite stop_recording error, proceeding..." >&2
                # Continue with transcription as above
                AUDIO_SIZE=$(stat -c%s "$AUDIO_FILE" 2>/dev/null || echo "0")
                if [ "$AUDIO_SIZE" -gt 1000 ]; then
                    TEXT=$(transcribe)
                    if [ $? -eq 0 ] && [ -n "$TEXT" ]; then
                        insert_text "$TEXT"
                        echo "✅ Successfully processed despite stop error: $TEXT" >&2
                    fi
                fi
                rm -f "$AUDIO_FILE"
                echo "IDLE" > "$STATUS_FILE"
            else
                echo "No recording was active or audio file missing" >&2
                notify-send "Whispo" "⚠️ No active recording found" -t 2000
                echo "IDLE" > "$STATUS_FILE"
            fi
        fi
        ;;
        
    toggle)
        # Toggle recording
        STATUS=$(cat "$STATUS_FILE" 2>/dev/null || echo "IDLE")
        
        if [ "$STATUS" = "RECORDING" ]; then
            $0 stop
        else
            $0 start &
        fi
        ;;
        
    status)
        # Show status
        STATUS=$(cat "$STATUS_FILE" 2>/dev/null || echo "IDLE")
        echo "Status: $STATUS"
        ;;
        
    *)
        echo "Usage: $0 {start|stop|toggle|status}"
        echo ""
        echo "  start  - start recording"
        echo "  stop   - stop recording and transcribe"
        echo "  toggle - toggle recording"
        echo "  status - show current status"
        exit 1
        ;;
esac