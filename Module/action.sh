#!/system/bin/sh
MODDIR=${0%/*}
TOGGLE_FILE="$MODDIR/disable_service"
DEBUG_FILE="$MODDIR/enable_debug"
LOG_FILE="$MODDIR/debug.log"
TMP_EVENT="/data/local/tmp/fix_hdr_events"

is_service_running() {
  pgrep -f "$MODDIR/service.sh" > /dev/null 2>&1
}

get_current_overlay_mode() {
  if grep -q "is_hdr_active" "$MODDIR/service.sh" 2>/dev/null; then
    echo "hdr_only"
  else
    echo "always"
  fi
}

check_key() {
  local delay=${1:-10}
  rm -f "$TMP_EVENT"
  timeout $delay getevent -lqc 1 > "$TMP_EVENT" 2>/dev/null
  if grep -q "KEY_VOLUMEUP *DOWN" "$TMP_EVENT"; then
      return 0
  elif grep -q "KEY_VOLUMEDOWN *DOWN" "$TMP_EVENT"; then
      return 1
  fi
  return 2
}

get_menu_text() {
  case $1 in
    1) 
      if [ -f "$TOGGLE_FILE" ]; then
        echo "Start Service (Currently: STOPPED)"
      elif ! is_service_running; then
        echo "Check Service Status (Currently: CRASHED/UNEXPECTED STOP)"
      else
        echo "Stop Service (Currently: ACTIVE)"
      fi
      ;;
    2) echo "Force Restart service.sh Process";;
    3)
      if [ -f "$DEBUG_FILE" ]; then
        echo "Disable Debug Logging (Currently: ENABLED)"
      else
        echo "Enable Debug Logging (Currently: DISABLED)"
      fi
      ;;
    4)
      if [ "$(get_current_overlay_mode)" = "hdr_only" ]; then
        echo "Switch to Always Disable Mode (Currently: HDR-Only Mode)"
      else
        echo "Switch to HDR-Only Mode (Currently: Always Disable Mode)"
      fi
      ;;
    5) echo "View Recent Debug Logs";;
    6) echo "Exit Menu";;
  esac
}

MAX_ITEMS=6

echo "========================================"
echo "    Fix HDR Volume Control Menu         "
echo "========================================"
echo "Available Functions:"
i=1
while [ $i -le $MAX_ITEMS ]; do
  echo "  [$i] $(get_menu_text $i)"
  i=$((i + 1))
done
echo "----------------------------------------"
echo " PRESS VOLUME DOWN TO BEGIN SETUP "
echo "----------------------------------------"

# Wait for Vol Down to start
while true; do
  check_key 60
  [ $? -eq 1 ] && break
done

echo ""
echo "ENTERING SELECTION MODE"
echo "  Vol DOWN = Next Option"
echo "  Vol UP   = Confirm Selection"
echo "========================================"

POS=1
echo ""
echo "-> Current Choice: [ $(get_menu_text $POS) ]"

while true; do
  check_key 30
  INPUT=$?

  if [ $INPUT -eq 0 ]; then
    echo ""
    echo "****************************************"
    echo " SELECTED: $(get_menu_text $POS)"
    echo "****************************************"

    case $POS in
      1)
        if [ -f "$TOGGLE_FILE" ]; then
          # --- START SERVICE ---
          rm -f "$TOGGLE_FILE"
          sh "$MODDIR/service.sh" &
          echo "[+] Service STARTED (PID: $(pgrep -f "$MODDIR/service.sh"))"
        elif ! is_service_running; then
          # --- CRASH DETECTED ---
          echo "[!] ERROR: service.sh is NOT running!"
          echo "[!] The process crashed or was killed externally."
          echo "[!] Use Option [2] 'Force Restart' to relaunch it."
        else
          # --- STOP SERVICE ---
          touch "$TOGGLE_FILE"
          pkill -f "$MODDIR/service.sh" 2>/dev/null
          service call SurfaceFlinger 1008 i32 0 > /dev/null 2>&1
          echo "[-] Process KILLED and Service STOPPED."
        fi
        ;;
      2)
        pkill -f "$MODDIR/service.sh" 2>/dev/null
        sleep 1
        sh "$MODDIR/service.sh" &
        echo "[+] service.sh re-launched in background!"
        ;;
      3)
        if [ -f "$DEBUG_FILE" ]; then
          rm -f "$DEBUG_FILE" "$LOG_FILE"
          echo "[-] Debug logging is now DISABLED."
        else
          touch "$DEBUG_FILE"
          echo "[+] Debug logging is now ENABLED."
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Fix HDR Debug Logging Enabled ===" > "$LOG_FILE"
        fi
        ;;
      4)
        CURRENT_MODE=$(get_current_overlay_mode)
        if [ "$CURRENT_MODE" = "hdr_only" ]; then
          TARGET_SRC="$MODDIR/service1.sh"
          NEW_MODE_NAME="Always Disable"
        else
          TARGET_SRC="$MODDIR/service2.sh"
          NEW_MODE_NAME="HDR-Only"
        fi

        if [ ! -f "$TARGET_SRC" ]; then
          echo "[!] ERROR: $TARGET_SRC not found. Cannot switch mode."
        else
          pkill -f "$MODDIR/service.sh" 2>/dev/null
          cp -f "$TARGET_SRC" "$MODDIR/service.sh"
          chmod 755 "$MODDIR/service.sh"
          echo "[*] Switched to $NEW_MODE_NAME mode."

          if [ ! -f "$TOGGLE_FILE" ]; then
            sh "$MODDIR/service.sh" &
            echo "[+] Service restarted with new mode (PID: $(pgrep -f "$MODDIR/service.sh"))"
          else
            echo "[i] Service is currently STOPPED; new mode will apply next time it's started."
          fi
        fi
        ;;
      5)
        echo "--- Recent Debug Logs ---"
        if [ -f "$DEBUG_FILE" ] && [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
          tail -n 12 "$LOG_FILE"
        else
          echo "No log entries. Debug mode is currently DISABLED."
        fi
        ;;
      6)
        echo "Exiting menu..."
        ;;
    esac
    break

  elif [ $INPUT -eq 1 ]; then
    POS=$((POS + 1))
    [ $POS -gt $MAX_ITEMS ] && POS=1
    echo "-> Current Choice: [ $(get_menu_text $POS) ]"
  fi
done

rm -f "$TMP_EVENT"
