#!/usr/bin/env bash
# waybarCheck.sh
# Kills waybar if it's running but has no active layer-shell surface

pid=$(pgrep -x waybar)

if [[ -z "$pid" ]]; then
    waybar & disown
fi

# Check if waybar registered a layer-shell surface on any output
has_layer=$(hyprctl layers -j | jq '[.[][] | select(.namespace == "waybar")] | length')

if [[ "$has_layer" -eq 0 ]]; then
    echo "waybar pid $pid alive but no layer-shell surface found — killing"
    kill -9 "$pid"
    waybar & disown
fi