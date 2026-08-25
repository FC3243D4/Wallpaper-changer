#!/usr/bin/env bash
# gtkPatcher.sh
# Patches GTK themes with the accent color.
# Usage: gtkPatcher.sh <hex_color>
# Example: gtkPatcher.sh a986d3

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

# Calculate RGB components
R=$((16#${color:0:2}))
G=$((16#${color:2:2}))
B=$((16#${color:4:2}))
accent="#$color"

# Patch (or bootstrap+patch) ~/.config/gtk-{3,4}.0/colors.css.
# These override files take precedence over the theme's own gtk.css for
# many apps (notably GTK4/libadwaita via the compiled gtk-4.0/gtk.css that
# @imports colors.css), so they must be actively patched, not just touched.
for gtk_ver in gtk-3.0 gtk-4.0; do
    cfg_colors="$HOME/.config/$gtk_ver/colors.css"
    mkdir -p "$HOME/.config/$gtk_ver"

    # Bootstrap from the system theme's colors.css if the user doesn't have one yet
    if [ ! -f "$cfg_colors" ]; then
        sys_colors="/usr/share/themes/Breeze-Dark/$gtk_ver/colors.css"
        if [ -f "$sys_colors" ]; then
            cp "$sys_colors" "$cfg_colors"
            echo "  $cfg_colors bootstrapped from $sys_colors"
        else
            touch "$cfg_colors"
        fi
    fi

    [ -s "$cfg_colors" ] && sed -i \
        -e "s/link_color_breeze #[0-9a-fA-F]\{6\}/link_color_breeze #$color/g" \
        -e "s/theme_view_hover_decoration_color_breeze #[0-9a-fA-F]\{6\}/theme_view_hover_decoration_color_breeze #$color/g" \
        -e "s/theme_hovering_selected_bg_color_breeze #[0-9a-fA-F]\{6\}/theme_hovering_selected_bg_color_breeze #$color/g" \
        -e "s/theme_selected_bg_color_breeze #[0-9a-fA-F]\{6\}/theme_selected_bg_color_breeze #$color/g" \
        -e "s/theme_view_active_decoration_color_breeze #[0-9a-fA-F]\{6\}/theme_view_active_decoration_color_breeze #$color/g" \
        -e "s/theme_button_decoration_focus_backdrop_breeze #[0-9a-fA-F]\{6\}/theme_button_decoration_focus_backdrop_breeze #$color/g" \
        -e "s/theme_button_decoration_focus_breeze #[0-9a-fA-F]\{6\}/theme_button_decoration_focus_breeze #$color/g" \
        -e "s/theme_button_decoration_hover_backdrop_breeze #[0-9a-fA-F]\{6\}/theme_button_decoration_hover_backdrop_breeze #$color/g" \
        -e "s/theme_button_decoration_hover_breeze #[0-9a-fA-F]\{6\}/theme_button_decoration_hover_breeze #$color/g" \
        "$cfg_colors"

    # libadwaita (GTK4) ignores the _breeze variables above entirely and only
    # reads accent_color / accent_bg_color / accent_fg_color. Patch in place
    # if already present (idempotent across repeated runs), else append once.
    if [ "$gtk_ver" = "gtk-4.0" ] && [ -f "$cfg_colors" ]; then
        if grep -q "@define-color accent_bg_color" "$cfg_colors"; then
            sed -i \
                -e "s/@define-color accent_color #[0-9a-fA-F]\{6\};/@define-color accent_color #$color;/g" \
                -e "s/@define-color accent_bg_color #[0-9a-fA-F]\{6\};/@define-color accent_bg_color #$color;/g" \
                "$cfg_colors"
        else
            {
                echo ""
                echo "@define-color accent_color #$color;"
                echo "@define-color accent_bg_color #$color;"
                echo "@define-color accent_fg_color #ffffff;"
            } >> "$cfg_colors"
        fi
    fi
done

# Patch Breeze-Dark GTK theme (always from system copy, single sed pass)
GTK_BASE="$HOME/.local/share/themes/Breeze-Dark"
GTK_SYS_BASE="/usr/share/themes/Breeze-Dark"

# Bootstrap local theme if it doesn't exist
if [ ! -d "$GTK_BASE" ]; then
    if [ -d "$GTK_SYS_BASE" ]; then
        mkdir -p "$HOME/.local/share/themes"
        cp -r "$GTK_SYS_BASE" "$GTK_BASE"
        echo "  Breeze-Dark GTK theme copied to $GTK_BASE (was missing — fresh install bootstrap)"
    else
        echo "  $GTK_SYS_BASE not found, cannot bootstrap local GTK theme override"
    fi
fi

if [ -d "$GTK_BASE" ]; then
    for gtk_ver in gtk-3.0 gtk-4.0; do
        sys_css="/usr/share/themes/Breeze-Dark/$gtk_ver/gtk.css"
        usr_css="$GTK_BASE/$gtk_ver/gtk.css"
        [ -f "$sys_css" ] && sed \
            -e "s/theme_view_hover_decoration_color_breeze #[0-9a-fA-F]*/theme_view_hover_decoration_color_breeze #$color/g" \
            -e "s/theme_hovering_selected_bg_color_breeze #[0-9a-fA-F]*/theme_hovering_selected_bg_color_breeze #$color/g" \
            -e "s/theme_selected_bg_color_breeze #[0-9a-fA-F]*/theme_selected_bg_color_breeze #$color/g" \
            -e "s/theme_view_active_decoration_color_breeze #[0-9a-fA-F]*/theme_view_active_decoration_color_breeze #$color/g" \
            -e "s/theme_unfocused_selected_bg_color_alt_breeze #[0-9a-fA-F]*/theme_unfocused_selected_bg_color_alt_breeze #$color/g" \
            -e "s/theme_button_decoration_hover_breeze  #[0-9a-fA-F]*/theme_button_decoration_hover_breeze  #$color/g" \
            -e "s/theme_button_decoration_focus_breeze  #[0-9a-fA-F]*/theme_button_decoration_focus_breeze  #$color/g" \
            -e "s/theme_button_decoration_hover_backdrop_breeze  #[0-9a-fA-F]*/theme_button_decoration_hover_backdrop_breeze  #$color/g" \
            -e "s/theme_button_decoration_focus_backdrop_breeze  #[0-9a-fA-F]*/theme_button_decoration_focus_backdrop_breeze  #$color/g" \
            -e "s/rgba([0-9]*, [0-9]*, [0-9]*,/rgba($R, $G, $B,/g" \
            "$sys_css" > "$usr_css"
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
current_theme=$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")
gsettings set org.gnome.desktop.interface gtk-theme ''
sleep 0.1
gsettings set org.gnome.desktop.interface gtk-theme "$current_theme"
rm -rf "$HOME/.cache/gtk-3.0" "$HOME/.cache/gtk-4.0"
systemctl --user restart xdg-desktop-portal-gtk
systemctl --user restart xdg-desktop-portal

echo "GTK theme patched with $accent"