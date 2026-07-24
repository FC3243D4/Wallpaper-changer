#!/usr/bin/env bash

# Special-cased instead of going through the generic appRestarter.sh
# mechanism: killing only the GUI orphans its onedrive --monitor child,
# which keeps the account's lock file and blocks a plain relaunch.

_t0=$(date +%s%N)

pkill -f "onedrivegui"
pkill -f "onedrive .*--monitor"
while pgrep -f "onedrivegui|onedrive .*--monitor" >/dev/null 2>&1; do
    sleep 0.1
done
onedrivegui >/dev/null 2>&1 &
disown

_t1=$(date +%s%N)
echo "[timing] onedrive restart: $(awk -v a="$_t0" -v b="$_t1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2
