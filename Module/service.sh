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
    DEBUG_FILE="$MODDIR/enable_debug"
    LOG_FILE="$MODDIR/debug.log"

    log_msg() {
        [ -f "$DEBUG_FILE" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    }

    is_screen_on() {
        local bl_power
        bl_power=$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -n 1)
        [ -n "$bl_power" ] && [ "$bl_power" -eq 0 ]
    }

    trap 'service call SurfaceFlinger 1008 i32 0 > /dev/null 2>&1; log_msg "=== Service Stopped ==="; exit 0' EXIT INT TERM

    log_msg "=== Service Started ==="

    CURRENT_STATE=0

    while true; do
        sleep 2.5

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
                sleep 5
                if [ -f "$TOGGLE_FILE" ]; then
                    exit 0
                fi
            done

            log_msg "SCREEN ON: Monitoring restored to normal."
        fi

        if [ ! -f "$CONFIG_FILE" ]; then
            continue
        fi

        DISPLAY_DUMP=$(dumpsys window displays 2>/dev/null)

        if echo "$DISPLAY_DUMP" | grep -iE -q "isKeyguardShowing=true|udfps|fingerprint|fod|biometric"; then
            if [ "$CURRENT_STATE" -eq 1 ]; then
                service call SurfaceFlinger 1008 i32 0 > /dev/null 2>&1
                CURRENT_STATE=0
                log_msg "SECURITY UI DETECTED: Restored HW Overlays."
            fi
            continue
        fi

        CURRENT_FOCUS=$(echo "$DISPLAY_DUMP" | grep -E "mCurrentFocus|mFocusedApp" | head -n 1)

        MATCH_FOUND=0
        MATCHED_PKG=""

        while IFS= read -r pkg || [ -n "$pkg" ]; do
            [ -z "$pkg" ] && continue
            case "$pkg" in \#*) continue ;; esac

            if echo "$CURRENT_FOCUS" | grep -q "$pkg"; then
                MATCH_FOUND=1
                MATCHED_PKG="$pkg"
                break
            fi
        done < "$CONFIG_FILE"

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