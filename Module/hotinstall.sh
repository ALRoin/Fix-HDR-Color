#!/bin/sh
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
MODDIR=${0%/*}
CONFIG_FILE="$MODDIR/config.txt"

echo "fix-hdr: live hot-install hook triggered" >> /dev/kmsg

if [ ! -f "$CONFIG_FILE" ]; then
    echo "fix-hdr: Creating config file at $CONFIG_FILE" >> /dev/kmsg
    echo "# Fix HDR User Configuration" > "$CONFIG_FILE"
    echo "# Add your HDR configuration settings below." >> "$CONFIG_FILE"
    chmod 666 "$CONFIG_FILE"
fi

if [ -f "$MODDIR/service.sh" ]; then
    echo "fix-hdr: launching service.sh live" >> /dev/kmsg
    sh "$MODDIR/service.sh" &
else
    echo "fix-hdr: WARNING - service.sh not found, nothing to launch" >> /dev/kmsg
fi

echo "fix-hdr: hot-install completed successfully" >> /dev/kmsg
