#!/usr/bin/env bash
# OneDriveRestarter.sh
# Special-cased instead of going through AppRestarter.sh's generic
# mechanism: killing only the GUI orphans its `onedrive --monitor` child,
# which keeps the account's lock file and blocks a plain relaunch.

startTime=$(date +%s%N)

echo "Restarting OneDriveGUI..."
pkill -f "onedrivegui"
pkill -f "onedrive .*--monitor"
while pgrep -f "onedrivegui|onedrive .*--monitor" >/dev/null 2>&1; do
    sleep 0.1
done
onedrivegui >/dev/null 2>&1 &
disown
echo "OneDriveGUI relaunched"

endTime=$(date +%s%N)
echo "[timing] onedrive restart: $(awk -v a="$startTime" -v b="$endTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2