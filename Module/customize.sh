#!/bin/sh

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH

export MODULE_HOT_INSTALL_REQUEST="true"
export MODULE_HOT_RUN_SCRIPT="hotinstall.sh"

ui_print "- Preparing Fix HDR..."

TMP_EVENT="/data/local/tmp/fix_hdr_install_events"

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

get_name() {
  case $1 in
    1) echo "Always disable HW overlays when a target app is in the foreground";;
    2) echo "Only disable HW overlays when HDR video is playing in a selected target app (Recommended)";;
  esac
}

get_mode() {
  case $1 in
    1) echo "always";;
    2) echo "hdr_only";;
  esac
}

MAX_ITEMS=2

ui_print "----------------------------------------"
ui_print "     FIX HDR - OVERLAY MODE SETUP        "
ui_print "----------------------------------------"
ui_print "Available modes:"
i=1
while [ $i -le $MAX_ITEMS ]; do
  ui_print "  [$i] $(get_name $i)"
  i=$((i + 1))
done
ui_print "----------------------------------------"
ui_print " PRESS VOLUME DOWN TO BEGIN SETUP "
ui_print "----------------------------------------"

# Wait for Vol Down to start
while true; do
  check_key 60
  [ $? -eq 1 ] && break
done

ui_print ""
ui_print "ENTERING SELECTION MODE"
ui_print "  Vol UP   = Confirm Selection"
ui_print "  Vol DOWN = Next Option"
ui_print ""

POS=1
ui_print "Current Choice: [ $(get_name $POS) ]"

while true; do
  check_key 300
  INPUT=$?

  if [ $INPUT -eq 0 ]; then
    # CONFIRM SELECTION
    ui_print ""
    ui_print "**********************************"
    ui_print " SELECTED: $(get_name $POS)"
    ui_print "**********************************"
    break

  elif [ $INPUT -eq 1 ]; then
    # NEXT OPTION
    POS=$((POS + 1))
    [ $POS -gt $MAX_ITEMS ] && POS=1
    ui_print "Current Choice: [ $(get_name $POS) ]"
  fi
done

CHOSEN_MODE=$(get_mode $POS)

if [ "$CHOSEN_MODE" = "always" ]; then
    SRC="$MODPATH/service1.sh"
else
    SRC="$MODPATH/service2.sh"
fi

if [ -f "$SRC" ]; then
    cp -f "$SRC" "$MODPATH/service.sh"
    set_perm "$MODPATH/service.sh" 0 0 0755
    ui_print "- Overlay mode set to: $(get_name $POS)"
else
    ui_print "! WARNING: $SRC not found in module package."
    ui_print "! service.sh was left unchanged."
fi

rm -f "$TMP_EVENT"

ui_print "- Staging complete. Initializing live hot-install..."
