#!/usr/bin/env bash
# discordPatcher.sh <hex-color-without-hash>
# Recolors Vesktop's Discord brand/control accent via QuickCSS.
set -euo pipefail

color="${1:?ERROR: discordPatcher.sh requires a hex color argument}"
color="${color#\#}"

# Locate quickCss.css — native package first, then flatpak
if [ -d "$HOME/.config/vesktop" ]; then
    QUICKCSS="$HOME/.config/vesktop/settings/quickCss.css"
elif [ -d "$HOME/.var/app/dev.vencord.Vesktop" ]; then
    QUICKCSS="$HOME/.var/app/dev.vencord.Vesktop/config/vesktop/settings/quickCss.css"
else
    QUICKCSS="$HOME/.config/vesktop/settings/quickCss.css"
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

MARK_START="/* >>> themeRefresher accent (auto-generated, do not edit) >>> */"
MARK_END="/* <<< themeRefresher accent <<< */"

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