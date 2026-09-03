#!/usr/bin/env bash
# discordPatcher.sh <hex-color-without-hash>
# Recolors Vesktop's Discord brand/control accent via QuickCSS.
#
# Skipped (and any previous patch removed) if the Midnight Discord theme
# is enabled — Midnight already defines its own accent palette, and this
# script's blanket overrides would fight with it instead of complementing it.
set -euo pipefail

color="${1:?ERROR: discordPatcher.sh requires a hex color argument}"
color="${color#\#}"

# Locate Vesktop's config dir — native package first, then flatpak
if [ -d "$HOME/.config/vesktop" ]; then
    vesktopConfigDir="$HOME/.config/vesktop"
elif [ -d "$HOME/.var/app/dev.vencord.Vesktop" ]; then
    vesktopConfigDir="$HOME/.var/app/dev.vencord.Vesktop/config/vesktop"
else
    vesktopConfigDir="$HOME/.config/vesktop"
fi

quickCssFile="$vesktopConfigDir/settings/quickCss.css"
vesktopSettingsFile="$vesktopConfigDir/settings.json"

markStart="/* >>> themeRefresher accent (auto-generated, do not edit) >>> */"
markEnd="/* <<< themeRefresher accent <<< */"

remove_patch_block() {
    if [ -f "$quickCssFile" ] && grep -qF "$markStart" "$quickCssFile" 2>/dev/null; then
        awk -v start="$markStart" -v end="$markEnd" '
            $0 == start {skip=1; next}
            $0 == end {skip=0; next}
            skip {next}
            {print}
        ' "$quickCssFile" > "$quickCssFile.tmp" && mv "$quickCssFile.tmp" "$quickCssFile"
        echo "Removed previous discordPatcher accent block from $quickCssFile."
    fi
}

# --- Midnight Discord theme detection ---
# UNVERIFIED: assumes Vencord's settings.json "enabledThemes" schema (same
# assumption install.sh's "Configure Vesktop" section makes). If detection
# ever breaks, check that schema first.
if [ -f "$vesktopSettingsFile" ] && command -v jq &>/dev/null; then
    if jq -e '(.enabledThemes // []) | index("midnight-discord.css")' "$vesktopSettingsFile" &>/dev/null; then
        echo "Midnight Discord theme is enabled — it already sets its own accent colors."
        echo "Skipping discordPatcher accent patch to avoid conflicting with it."
        remove_patch_block
        exit 0
    fi
elif [ -f "$vesktopSettingsFile" ]; then
    # jq not available — plain string search. Less precise (can't tell a
    # commented-out entry from a real one) but still catches the common case.
    if grep -qF '"midnight-discord.css"' "$vesktopSettingsFile" 2>/dev/null; then
        echo "Midnight Discord theme appears to be enabled (jq not found, used a plain text match)."
        echo "Skipping discordPatcher accent patch to avoid conflicting with it."
        remove_patch_block
        exit 0
    fi
fi

mkdir -p "$(dirname "$quickCssFile")"
touch "$quickCssFile"

# Derive lighter (hover) / darker (active) shades by blending toward white/black
read -r hover active <<< "$(python3 - "$color" << 'PYEOF'
import sys
c = sys.argv[1]
r, g, b = (int(c[i:i+2], 16) for i in (0, 2, 4))
def blend(r, g, b, target, amt):
    tr, tg, tb = target
    return (round(r + (tr - r) * amt), round(g + (tg - g) * amt), round(b + (tb - b) * amt))
hr, hg, hb = blend(r, g, b, (255, 255, 255), 0.12)
ar, ag, ab = blend(r, g, b, (0, 0, 0), 0.15)
print(f"#{hr:02x}{hg:02x}{hb:02x} #{ar:02x}{ag:02x}{ab:02x}")
PYEOF
)"

# Applied on * (not :root): Discord's own components re-declare these
# custom properties locally without !important, and a local declaration
# always beats an inherited value regardless of !important — forcing it
# on every element is what actually wins.
block="$markStart
*, *::before, *::after {
  --background-brand: #$color !important;
  --background-brand-hover: $hover !important;
  --background-brand-active: $active !important;
  --text-brand: #$color !important;
  --icon-brand: #$color !important;
  --border-brand: #$color !important;
  --focus-brand: #$color !important;
  --button-brand-background: #$color !important;
  --button-brand-background-hover: $hover !important;
  --button-brand-background-active: $active !important;
  --brand-500: #$color !important;

  --control-primary-background-default: #$color !important;
  --control-primary-background-hover: $hover !important;
  --control-primary-background-active: $active !important;
  --control-primary-border-default: #$color !important;
  --control-primary-border-hover: $hover !important;
  --control-primary-border-active: $active !important;
}
$markEnd"

if grep -qF "$markStart" "$quickCssFile" 2>/dev/null; then
    awk -v start="$markStart" -v end="$markEnd" -v block="$block" '
        $0 == start {print block; skip=1; next}
        $0 == end {skip=0; next}
        skip {next}
        {print}
    ' "$quickCssFile" > "$quickCssFile.tmp" && mv "$quickCssFile.tmp" "$quickCssFile"
else
    printf '\n%s\n' "$block" >> "$quickCssFile"
fi

echo "Discord/Vesktop accent patched -> #$color"