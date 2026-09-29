#!/usr/bin/env bash

# Wlogout icons — hovered/standard pairs with a dimmed derived shade,
# written to wlogout's own config dir rather than the icon theme.
patch_wlogout_icons() {
    wlogoutIconsDir="$HOME/.config/wlogout/icons"
    if command -v wlogout >/dev/null 2>&1; then
        mkdir -p "$wlogoutIconsDir"

        # "Off"/standard state: same hue as accent, dimmed via reduced saturation + value, so it reads as "the same color, turned down" rather than an unrelated gray.
        standard=$(python3 -c "
import colorsys
h = '$accent'.lstrip('#')
r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
hh, s, v = colorsys.rgb_to_hsv(r, g, b)
nr, ng, nb = colorsys.hsv_to_rgb(hh, s * 0.5, v * 0.35)
print('#{:02x}{:02x}{:02x}'.format(int(nr*255), int(ng*255), int(nb*255)))
")

        # Hovered (full accent)
        sed "s/currentColor/$accent/g"   "$iconsDir/lock_base_icon.svg"     > "$wlogoutIconsDir/lock-hovered.svg"
        sed "s/currentColor/$accent/g"   "$iconsDir/reboot_base_icon.svg"   > "$wlogoutIconsDir/reboot-hovered.svg"
        sed "s/currentColor/$accent/g"   "$iconsDir/power_base_icon.svg"    > "$wlogoutIconsDir/power-hovered.svg"
        sed "s/currentColor/$accent/g"   "$iconsDir/logout_base_icon.svg"   > "$wlogoutIconsDir/logout-hovered.svg"
        sed "s/currentColor/$accent/g"   "$iconsDir/sleep_base_icon.svg"    > "$wlogoutIconsDir/sleep-hovered.svg"
        sed "s/currentColor/$accent/g"   "$iconsDir/suspend_base_icon.svg"  > "$wlogoutIconsDir/suspend-hovered.svg"

        # Standard (dimmed)
        sed "s/currentColor/$standard/g" "$iconsDir/lock_base_icon.svg"     > "$wlogoutIconsDir/lock-standard.svg"
        sed "s/currentColor/$standard/g" "$iconsDir/reboot_base_icon.svg"   > "$wlogoutIconsDir/reboot-standard.svg"
        sed "s/currentColor/$standard/g" "$iconsDir/power_base_icon.svg"    > "$wlogoutIconsDir/power-standard.svg"
        sed "s/currentColor/$standard/g" "$iconsDir/logout_base_icon.svg"   > "$wlogoutIconsDir/logout-standard.svg"
        sed "s/currentColor/$standard/g" "$iconsDir/sleep_base_icon.svg"    > "$wlogoutIconsDir/sleep-standard.svg"
        sed "s/currentColor/$standard/g" "$iconsDir/suspend_base_icon.svg"  > "$wlogoutIconsDir/suspend-standard.svg"

        echo "Wlogout icons patched (standard=$standard, hovered=$accent)"
    fi
}
