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

R=$((16#${color:0:2}))
G=$((16#${color:2:2}))
B=$((16#${color:4:2}))
accent="#$color"

# Ensure GTK colors.css stubs exist to avoid warnings
touch "$HOME/.config/gtk-3.0/colors.css"
touch "$HOME/.config/gtk-4.0/colors.css"

# Patch Breeze-Dark GTK theme (always from system copy, single sed pass)
GTK_BASE="$HOME/.local/share/themes/Breeze-Dark"
GTK_SYS_BASE="/usr/share/themes/Breeze-Dark"

# On a fresh install, ~/.local/share/themes may not exist at all yet — the
# patch loop below only ever edits an existing local override, it never
# creates one. Without this, the whole block below silently no-ops every
# run (real symptom hit on a fresh laptop: nwg-look's widget preview
# stayed plain unmodified Breeze-Dark forever, no accent color ever
# applied, with no error anywhere — same shape of bug as the missing
# breeze-dark-accent/index.theme). Bootstrap by copying the full system
# theme once, so there's a real user-owned copy to patch going forward.
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