#!/usr/bin/env bash
# discordPatcher.sh <hex-color-without-hash>
# Recolors Vesktop's Discord brand/control accent via QuickCSS.
#
# Skips entirely (and removes any previously-applied patch) if the Midnight
# Discord theme is enabled. Midnight already defines its own full accent
# palette (--accent-1 through --accent-5, etc.) via the matugen
# midnight-discord.css template, so this script's blanket
# --background-brand/--control-primary-* overrides would fight with it
# rather than complement it.
set -euo pipefail

color="${1:?ERROR: discordPatcher.sh requires a hex color argument}"
color="${color#\#}"

# Locate Vesktop's config dir — native package first, then flatpak
if [ -d "$HOME/.config/vesktop" ]; then
    VESKTOP_CONFIG_DIR="$HOME/.config/vesktop"
elif [ -d "$HOME/.var/app/dev.vencord.Vesktop" ]; then
    VESKTOP_CONFIG_DIR="$HOME/.var/app/dev.vencord.Vesktop/config/vesktop"
else
    VESKTOP_CONFIG_DIR="$HOME/.config/vesktop"
fi

QUICKCSS="$VESKTOP_CONFIG_DIR/settings/quickCss.css"
VESKTOP_SETTINGS="$VESKTOP_CONFIG_DIR/settings.json"

MARK_START="/* >>> themeRefresher accent (auto-generated, do not edit) >>> */"
MARK_END="/* <<< themeRefresher accent <<< */"

_remove_patch_block() {
    if [ -f "$QUICKCSS" ] && grep -qF "$MARK_START" "$QUICKCSS" 2>/dev/null; then
        awk -v start="$MARK_START" -v end="$MARK_END" '
            $0 == start {skip=1; next}
            $0 == end {skip=0; next}
            skip {next}
            {print}
        ' "$QUICKCSS" > "$QUICKCSS.tmp" && mv "$QUICKCSS.tmp" "$QUICKCSS"
        echo "Removed previous discordPatcher accent block from $QUICKCSS."
    fi
}

# --- Midnight Discord theme detection ---
# UNVERIFIED: assumes Vencord's settings.json "enabledThemes" schema (same
# assumption as install.sh's "Configure Vesktop" section). If this ever
# stops correctly detecting Midnight, check that schema first.
if [ -f "$VESKTOP_SETTINGS" ] && command -v jq &>/dev/null; then
    if jq -e '(.enabledThemes // []) | index("midnight-discord.css")' "$VESKTOP_SETTINGS" &>/dev/null; then
        echo "Midnight Discord theme is enabled — it already sets its own accent colors."
        echo "Skipping discordPatcher accent patch to avoid conflicting with it."
        _remove_patch_block
        exit 0
    fi
elif [ -f "$VESKTOP_SETTINGS" ]; then
    # jq not available — fall back to a plain string search. Less precise
    # (e.g. can't tell a commented-out entry from a real one) but still
    # catches the common case.
    if grep -qF '"midnight-discord.css"' "$VESKTOP_SETTINGS" 2>/dev/null; then
        echo "Midnight Discord theme appears to be enabled (jq not found, used a plain text match)."
        echo "Skipping discordPatcher accent patch to avoid conflicting with it."
        _remove_patch_block
        exit 0
    fi
fi

mkdir -p "$(dirname "$QUICKCSS")"
touch "$QUICKCSS"

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

# Applied on * (not :root) because Discord's own components re-declare
# these custom properties locally without !important, and a local
# declaration always wins over an inherited value no matter how loud
# an ancestor's !important is. Forcing it on every element beats that.
block="$MARK_START
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
$MARK_END"

if grep -qF "$MARK_START" "$QUICKCSS" 2>/dev/null; then
    awk -v start="$MARK_START" -v end="$MARK_END" -v block="$block" '
        $0 == start {print block; skip=1; next}
        $0 == end {skip=0; next}
        skip {next}
        {print}
    ' "$QUICKCSS" > "$QUICKCSS.tmp" && mv "$QUICKCSS.tmp" "$QUICKCSS"
else
    printf '\n%s\n' "$block" >> "$QUICKCSS"
fi

echo "Discord/Vesktop accent patched -> #$color"