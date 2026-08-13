#!/system/bin/sh
MODDIR=${0%/*}
TOGGLE_FILE="$MODDIR/disable_service"

if [ -f "$TOGGLE_FILE" ]; then
    exit 0
fi

(
    until [ "$(getprop sys.boot_completed)" = "1" ]; do
        sleep 5
    done

    CONFIG_FILE="$MODDIR/config.txt"
    INTERVAL_FILE="$MODDIR/intervals.conf"
    DEBUG_FILE="$MODDIR/enable_debug"
    LOG_FILE="$MODDIR/debug.log"

    CONFIG_MTIME=""
    CONFIG_CONTENT=""
    INTERVAL_MTIME=""

    FOREGROUND_INTERVAL=2.5
    SCREENOFF_INTERVAL=5

    log_msg() {
        [ -f "$DEBUG_FILE" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    }

    is_screen_on() {
        local f bl_power=""
        for f in /sys/class/backlight/*/bl_power; do
            [ -r "$f" ] && read -r bl_power < "$f" && break
        done
        [ -n "$bl_power" ] && [ "$bl_power" -eq 0 ]
    }

    reload_config_if_changed() {
        local new_mtime
        new_mtime=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null)
        if [ "$new_mtime" != "$CONFIG_MTIME" ]; then
            CONFIG_CONTENT=$(cat "$CONFIG_FILE")
            CONFIG_MTIME="$new_mtime"
            log_msg "CONFIG RELOADED: mtime changed to $new_mtime."
        fi
    }

    reload_intervals_if_changed() {
        local new_mtime
        new_mtime=$(stat -c %Y "$INTERVAL_FILE" 2>/dev/null)
        if [ "$new_mtime" != "$INTERVAL_MTIME" ]; then
            [ -f "$INTERVAL_FILE" ] && . "$INTERVAL_FILE"
            INTERVAL_MTIME="$new_mtime"
            log_msg "INTERVALS RELOADED: FOREGROUND_INTERVAL=$FOREGROUND_INTERVAL SCREENOFF_INTERVAL=$SCREENOFF_INTERVAL"
        fi
    }

    trap 'service call SurfaceFlinger 1008 i32 0 > /dev/null 2>&1; log_msg "=== Service Stopped ==="; exit 0' EXIT INT TERM

    log_msg "=== Service Started ==="

    CURRENT_STATE=0

    while true; do
        reload_intervals_if_changed
        sleep "$FOREGROUND_INTERVAL"

        if [ -f "$TOGGLE_FILE" ]; then
            log_msg "Service STOPPED via disable_service flag."
            exit 0
        fi

        if ! is_screen_on; then
            log_msg "SCREEN OFF: Reduced monitoring frequency."

            if [ "$CURRENT_STATE" -eq 1 ]; then
                service call SurfaceFlinger 1008 i32 0 > /dev/null 2>&1
                CURRENT_STATE=0
                log_msg "SCREEN OFF: Restored HW Overlays."
            fi

            until is_screen_on; do
                sleep "$SCREENOFF_INTERVAL"
                if [ -f "$TOGGLE_FILE" ]; then
                    exit 0
                fi
            done

            log_msg "SCREEN ON: Monitoring restored to normal."
        fi

        if [ ! -f "$CONFIG_FILE" ]; then
            continue
        fi

        reload_config_if_changed

        DISPLAY_DUMP=$(dumpsys window displays 2>/dev/null)

        if echo "$DISPLAY_DUMP" | grep -iE -q "isKeyguardShowing=true|udfps|fingerprint|fod|biometric"; then
            if [ "$CURRENT_STATE" -eq 1 ]; then
                service call SurfaceFlinger 1008 i32 0 > /dev/null 2>&1
                CURRENT_STATE=0
                log_msg "SECURITY UI DETECTED: Restored HW Overlays."
            fi
            continue
        fi

        CURRENT_FOCUS=$(echo "$DISPLAY_DUMP" | grep -E "mCurrentFocus|mFocusedApp")

        MATCH_FOUND=0
        MATCHED_PKG=""

        while IFS= read -r pkg || [ -n "$pkg" ]; do
            [ -z "$pkg" ] && continue
            case "$pkg" in \#*) continue ;; esac

            case "$CURRENT_FOCUS" in
                *"$pkg"*)
                    MATCH_FOUND=1
                    MATCHED_PKG="$pkg"
                    break
                    ;;
            esac
        done <<EOF
$CONFIG_CONTENT
EOF

        if [ "$MATCH_FOUND" -eq 1 ]; then
            if [ "$CURRENT_STATE" -eq 0 ]; then
                service call SurfaceFlinger 1008 i32 1 > /dev/null 2>&1
                CURRENT_STATE=1
                log_msg "MATCH DETECTED: $MATCHED_PKG -> HW Overlays Disabled"
            fi
        else
            if [ "$CURRENT_STATE" -eq 1 ]; then
                service call SurfaceFlinger 1008 i32 0 > /dev/null 2>&1
                CURRENT_STATE=0
                log_msg "APP EXIT: Restored HW Overlays"
            fi
        fi
    done
) &
