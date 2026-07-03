#!/usr/bin/env bash
# ferdiumPatcher.sh
# Patches Ferdium settings with the accent color.
# Usage: ferdiumPatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#$color"
FERDIUM_SETTINGS="$HOME/.config/Ferdium/config/settings.json"

if [ ! -f "$FERDIUM_SETTINGS" ]; then
    echo "Ferdium settings not found, skipping"
    exit 0
fi

jq --arg color "$accent" \
    '.accentColor = $color | .progressbarAccentColor = $color' \
    "$FERDIUM_SETTINGS" > /tmp/ferdium-settings.tmp \
    && mv /tmp/ferdium-settings.tmp "$FERDIUM_SETTINGS"

echo "Ferdium patched with $accent"
