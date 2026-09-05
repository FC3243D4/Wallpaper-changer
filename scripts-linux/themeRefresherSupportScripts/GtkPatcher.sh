#!/usr/bin/env bash
# GtkPatcher.sh
# Recolors GTK3/GTK4 (incl. libadwaita) with the accent color, patches the
# local Breeze-Dark GTK theme copy, and nudges GTK apps to reload it.
# Usage: GtkPatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

r=$((16#${color:0:2}))
g=$((16#${color:2:2}))
b=$((16#${color:4:2}))
accent="#$color"

# Patch (or bootstrap+patch) ~/.config/gtk-{3,4}.0/colors.css. These
# overrides take precedence over the theme's own gtk.css for many apps
# (notably GTK4/libadwaita, whose compiled gtk.css @imports colors.css).
for gtkVer in gtk-3.0 gtk-4.0; do
    userColorsFile="$HOME/.config/$gtkVer/colors.css"
    mkdir -p "$HOME/.config/$gtkVer"

    if [ ! -f "$userColorsFile" ]; then
        systemColorsFile="/usr/share/themes/Breeze-Dark/$gtkVer/colors.css"
        if [ -f "$systemColorsFile" ]; then
            cp "$systemColorsFile" "$userColorsFile"
            echo "  $userColorsFile bootstrapped from $systemColorsFile"
        else
            touch "$userColorsFile"
        fi
    fi

    [ -s "$userColorsFile" ] && sed -i \
        -e "s/link_color_breeze #[0-9a-fA-F]\{6\}/link_color_breeze #$color/g" \
        -e "s/theme_view_hover_decoration_color_breeze #[0-9a-fA-F]\{6\}/theme_view_hover_decoration_color_breeze #$color/g" \
        -e "s/theme_hovering_selected_bg_color_breeze #[0-9a-fA-F]\{6\}/theme_hovering_selected_bg_color_breeze #$color/g" \
        -e "s/theme_selected_bg_color_breeze #[0-9a-fA-F]\{6\}/theme_selected_bg_color_breeze #$color/g" \
        -e "s/theme_view_active_decoration_color_breeze #[0-9a-fA-F]\{6\}/theme_view_active_decoration_color_breeze #$color/g" \
        -e "s/theme_button_decoration_focus_backdrop_breeze #[0-9a-fA-F]\{6\}/theme_button_decoration_focus_backdrop_breeze #$color/g" \
        -e "s/theme_button_decoration_focus_breeze #[0-9a-fA-F]\{6\}/theme_button_decoration_focus_breeze #$color/g" \
        -e "s/theme_button_decoration_hover_backdrop_breeze #[0-9a-fA-F]\{6\}/theme_button_decoration_hover_backdrop_breeze #$color/g" \
        -e "s/theme_button_decoration_hover_breeze #[0-9a-fA-F]\{6\}/theme_button_decoration_hover_breeze #$color/g" \
        "$userColorsFile"

    # libadwaita (GTK4) ignores the _breeze variables above and only reads
    # accent_color/accent_bg_color/accent_fg_color. Patch in place if
    # already present (idempotent), else append once.
    if [ "$gtkVer" = "gtk-4.0" ] && [ -f "$userColorsFile" ]; then
        if grep -q "@define-color accent_bg_color" "$userColorsFile"; then
            sed -i \
                -e "s/@define-color accent_color #[0-9a-fA-F]\{6\};/@define-color accent_color #$color;/g" \
                -e "s/@define-color accent_bg_color #[0-9a-fA-F]\{6\};/@define-color accent_bg_color #$color;/g" \
                "$userColorsFile"
        else
            {
                echo ""
                echo "@define-color accent_color #$color;"
                echo "@define-color accent_bg_color #$color;"
                echo "@define-color accent_fg_color #ffffff;"
            } >> "$userColorsFile"
        fi
    fi
done

# Patch the local Breeze-Dark GTK theme copy (always regenerated from the
# system copy, single sed pass).
gtkThemeDir="$HOME/.local/share/themes/Breeze-Dark"
systemGtkThemeDir="/usr/share/themes/Breeze-Dark"

if [ ! -d "$gtkThemeDir" ]; then
    if [ -d "$systemGtkThemeDir" ]; then
        mkdir -p "$HOME/.local/share/themes"
        cp -r "$systemGtkThemeDir" "$gtkThemeDir"
        echo "  Breeze-Dark GTK theme copied to $gtkThemeDir (was missing — fresh install bootstrap)"
    else
        echo "  $systemGtkThemeDir not found, cannot bootstrap local GTK theme override"
    fi
fi

if [ -d "$gtkThemeDir" ]; then
    for gtkVer in gtk-3.0 gtk-4.0; do
        systemCss="/usr/share/themes/Breeze-Dark/$gtkVer/gtk.css"
        userCss="$gtkThemeDir/$gtkVer/gtk.css"
        [ -f "$systemCss" ] && sed \
            -e "s/theme_view_hover_decoration_color_breeze #[0-9a-fA-F]*/theme_view_hover_decoration_color_breeze #$color/g" \
            -e "s/theme_hovering_selected_bg_color_breeze #[0-9a-fA-F]*/theme_hovering_selected_bg_color_breeze #$color/g" \
            -e "s/theme_selected_bg_color_breeze #[0-9a-fA-F]*/theme_selected_bg_color_breeze #$color/g" \
            -e "s/theme_view_active_decoration_color_breeze #[0-9a-fA-F]*/theme_view_active_decoration_color_breeze #$color/g" \
            -e "s/theme_unfocused_selected_bg_color_alt_breeze #[0-9a-fA-F]*/theme_unfocused_selected_bg_color_alt_breeze #$color/g" \
            -e "s/theme_button_decoration_hover_breeze  #[0-9a-fA-F]*/theme_button_decoration_hover_breeze  #$color/g" \
            -e "s/theme_button_decoration_focus_breeze  #[0-9a-fA-F]*/theme_button_decoration_focus_breeze  #$color/g" \
            -e "s/theme_button_decoration_hover_backdrop_breeze  #[0-9a-fA-F]*/theme_button_decoration_hover_backdrop_breeze  #$color/g" \
            -e "s/theme_button_decoration_focus_backdrop_breeze  #[0-9a-fA-F]*/theme_button_decoration_focus_backdrop_breeze  #$color/g" \
            -e "s/rgba([0-9]*, [0-9]*, [0-9]*,/rgba($r, $g, $b,/g" \
            "$systemCss" > "$userCss"
    done
fi

# GTK treeview/sidebar selection colors
cat > "$HOME/.config/gtk-3.0/gtk.css" << EOF
treeview {
    background-color: #202326;
    color: #eff0f1;
}
treeview:selected {
    background-color: $accent;
}
treeview header button {
    background-color: #202326;
    color: #eff0f1;
    border-color: #2d3036;
}
.sidebar {
    background-color: #202326;
    color: #eff0f1;
}
.sidebar row:selected {
    background-color: $accent;
}
pathbar button {
    color: #eff0f1;
}
pathbar button:hover {
    background-color: #2d3036;
    color: #eff0f1;
}
EOF

# Nudge GTK apps to reload theme and clear cache
currentTheme=$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")
gsettings set org.gnome.desktop.interface gtk-theme ''
sleep 0.1
gsettings set org.gnome.desktop.interface gtk-theme "$currentTheme"
rm -rf "$HOME/.cache/gtk-3.0" "$HOME/.cache/gtk-4.0"
# Independent units — restart both in parallel instead of waiting on one first.
systemctl --user restart xdg-desktop-portal-gtk &
portalGtkPid=$!
systemctl --user restart xdg-desktop-portal &
portalPid=$!
wait "$portalGtkPid" "$portalPid"

echo "GTK theme patched with $accent"