#!/usr/bin/env bash

# Save Hyprland layout state before any restarts
if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
    "$HOME/.config/WallpaperChanger/hyprMasterLayoutPreservation.sh" save
fi

WALLPAPER="$HOME/.config/WallpaperChanger/.current_wallpaper"
BRIGHTNESS_THRESHOLD=20
color=""

# Find brightest matugen candidate without running full matugen each time
for i in 0 1 2 3 4; do
    candidate=$(matugen image "$WALLPAPER" --source-color-index $i --dry-run 2>/dev/null \
        | grep -oP '#\K[0-9a-fA-F]{6}' | head -1)

    # Fall back to reading cache if dry-run not supported
    if [ -z "$candidate" ]; then
        matugen image "$WALLPAPER" --source-color-index $i --quiet 2>/dev/null
        candidate=$(cat ~/.cache/matugen/source-color 2>/dev/null | tr -d '[:space:]')
    fi

    [ -z "$candidate" ] && continue

    R=$((16#${candidate:0:2}))
    G=$((16#${candidate:2:2}))
    B=$((16#${candidate:4:2}))
    brightness=$(( (R * 299 + G * 587 + B * 114) / 1000 ))
    echo "Candidate $i: #$candidate (brightness: $brightness)"

    if [ "$brightness" -ge "$BRIGHTNESS_THRESHOLD" ]; then
        color="$candidate"
        echo "Using candidate $i: #$color"
        break
    fi
done

# Fall back to dominantcolor if all candidates too dark
if [ -z "$color" ]; then
    echo "All matugen candidates too dark, falling back to dominantcolor..."
    colorLine="$($HOME/.config/WallpaperChanger/dominantcolor -m 1 -n 2 -e black -p dominant "$WALLPAPER" | grep -E '#')"
    color=$(echo "$colorLine" | tr -d '#')
fi

# Validate color before proceeding
if [ ${#color} -ne 6 ] || ! echo "$color" | grep -qE '^[0-9a-fA-F]{6}$'; then
    echo "ERROR: Invalid color '$color', aborting theme refresh"
    exit 1
fi

# Run matugen once with the final chosen color
matugen color hex "#$color" --quiet

colorLine="#$color"
color="${color,,}"
R=$((16#${color:0:2}))
G=$((16#${color:2:2}))
B=$((16#${color:4:2}))
accent="#$color"
echo "Final color: $accent"

# Apply color to OpenRGB (backgrounded — fire and forget)
if openrgb --version &>/dev/null; then
    openrgb -c "$color" >/dev/null 2>&1 &
    disown
fi

# Apply color to Logitech G devices (backgrounded — fire and forget)
if ratbagctl --version &>/dev/null; then
    (
        devices=($(ratbagctl list | grep -oP '^[\w-]+(?=:)'))
        for device in "${devices[@]}"; do
            profiles=($(ratbagctl "$device" info | grep -oP '^Profile \K\d+'))
            for profile in "${profiles[@]}"; do
                ratbagctl "$device" profile $profile led 0 set mode on color "$color"
            done
        done
    ) &
    disown
fi

# Ensure GTK colors.css stubs exist to avoid warnings
touch "$HOME/.config/gtk-3.0/colors.css"
touch "$HOME/.config/gtk-4.0/colors.css"

# 1. Patch BreezeDark.colors (always from clean base, single awk pass)
BREEZE_COLORS="$HOME/.local/share/color-schemes/BreezeDark.colors"
BREEZE_COLORS_BASE="${BREEZE_COLORS}.base"

[ ! -f "$BREEZE_COLORS_BASE" ] && [ -f "$BREEZE_COLORS" ] && cp "$BREEZE_COLORS" "$BREEZE_COLORS_BASE"

if [ -f "$BREEZE_COLORS_BASE" ]; then
    awk -v rgb="$R,$G,$B" '
        /^\[Colors:View\]/      { in_view=1; in_sel=0 }
        /^\[Colors:Selection\]/ { in_sel=1;  in_view=0 }
        /^\[/ && !/^\[Colors:View\]/ && !/^\[Colors:Selection\]/ { in_view=0; in_sel=0 }
        /^DecorationFocus=/     { print "DecorationFocus=" rgb; next }
        /^DecorationHover=/     { print "DecorationHover=" rgb; next }
        in_view && /^ForegroundActive=/ { print "ForegroundActive=" rgb; next }
        in_sel  && /^BackgroundNormal=/ { print "BackgroundNormal=" rgb; next }
        { print }
    ' "$BREEZE_COLORS_BASE" > "$BREEZE_COLORS"
fi

# 2. Patch qt6ct palette (always from clean base)
QT6CT_CONF="$HOME/.config/qt6ct/colors/BreezeDark.conf"
QT6CT_BASE="${QT6CT_CONF}.base"

[ ! -f "$QT6CT_BASE" ] && [ -f "$QT6CT_CONF" ] && cp "$QT6CT_CONF" "$QT6CT_BASE"
[ -f "$QT6CT_BASE" ] && sed "s/#ff3daee9/#ff$color/g" "$QT6CT_BASE" > "$QT6CT_CONF"

# 3. Patch kdeglobals
kwriteconfig6 --file kdeglobals --group "Colors:View"      --key "DecorationFocus"     "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:View"      --key "DecorationHover"     "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:View"      --key "ForegroundActive"    "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:Selection" --key "BackgroundNormal"    "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:Selection" --key "BackgroundAlternate" "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "General"          --key "AccentColor"         "$R,$G,$B"
qdbus6 org.kde.KGlobalSettings /KGlobalSettings notifyChange 0 0 2>/dev/null || true

# 3b. Patch Breeze-Dark GTK theme (always from system copy, single sed pass)
GTK_BASE="$HOME/.local/share/themes/Breeze-Dark"
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

# 3c. GTK treeview/sidebar selection colors
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

# 4. Patch icon SVGs (always from system, only ColorScheme-Accent)
ICON_DIR="$HOME/.local/share/icons/breeze-dark-accent"
for size in 16 22 24 32 48 64 96; do
    src="/usr/share/icons/breeze-dark/places/$size/folder.svg"
    dst="$ICON_DIR/places/$size/folder.svg"
    [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
done
src="/usr/share/icons/breeze-dark/mimetypes/64/inode-directory.svg"
dst="$ICON_DIR/mimetypes/64/inode-directory.svg"
[ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"

# 5. Patch VS Code
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
if [ -f "$VSCODE_SETTINGS" ]; then
    python3 - << EOF
import json
with open('$VSCODE_SETTINGS', 'r') as f:
    s = json.load(f)
s['workbench.colorCustomizations'] = {
    "list.activeSelectionBackground": "${accent}99",
    "list.hoverBackground":           "${accent}33",
    "list.focusBackground":           "${accent}99",
    "menu.selectionBackground":       "#00000000",
    "menu.selectionBorder":           "$accent",
    "menu.border":                    "${accent}33",
    "quickInputList.focusBackground": "${accent}99",
    "focusBorder":                    "$accent",
    "activityBar.activeBorder":       "$accent",
    "tab.activeBorderTop":            "$accent",
    "editorCursor.foreground":        "$accent",
    "selection.background":           "${accent}55"
}
with open('$VSCODE_SETTINGS', 'w') as f:
    json.dump(s, f, indent=4)
print('VS Code colors updated')
EOF
fi

# 6. Patch Zen Browser chrome
for ZEN_PROFILE in "$HOME/.zen/8ma66p8a.Default (release)" "$HOME/.zen/k71gdxvw.Default Profile"; do
    [ ! -d "$ZEN_PROFILE" ] && continue
    mkdir -p "$ZEN_PROFILE/chrome"
    cat > "$ZEN_PROFILE/chrome/userChrome.css" << EOF
/* Generated by themeRefresher */
:root {
    --lwt-accent-color: $accent !important;
    --toolbar-field-focus-border-color: $accent !important;
    --toolbar-field-color: #fcfcfc !important;
    --toolbar-field-focus-color: #fcfcfc !important;
    --toolbar-color: #fcfcfc !important;
    --urlbar-box-text-color: #fcfcfc !important;
}
#urlbar-input { color: #fcfcfc !important; }
::selection { background-color: $accent !important; color: #ffffff !important; }
EOF
    cat > "$ZEN_PROFILE/chrome/userContent.css" << EOF
/* Generated by themeRefresher */
::selection { background-color: $accent !important; color: #ffffff !important; }
EOF
    grep -q "toolkit.legacyUserProfileCustomizations.stylesheets" "$ZEN_PROFILE/prefs.js" 2>/dev/null || \
        echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$ZEN_PROFILE/prefs.js"
done

# 7. Patch SourceGit theme
SOURCEGIT_THEME="$HOME/.sourcegit/ForkDark.json"
SOURCEGIT_BASE="${SOURCEGIT_THEME}.base"
SOURCEGIT_PREFS="$HOME/.sourcegit/preference.json"

[ -f "$SOURCEGIT_PREFS" ] && python3 - << EOF
import json
with open('$SOURCEGIT_PREFS', 'r') as f:
    p = json.load(f)
p['ThemeOverrides'] = '$SOURCEGIT_THEME'
with open('$SOURCEGIT_PREFS', 'w') as f:
    json.dump(p, f, indent=4)
EOF

[ -f "$SOURCEGIT_BASE" ] && python3 - << EOF
import json, colorsys

def hex_to_hsv(h):
    r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return '#{:02X}{:02X}{:02X}'.format(int(r*255), int(g*255), int(b*255))

base_h, base_s, base_v = hex_to_hsv('$color')
s = max(base_s, 0.6)
v = max(base_v, 0.75)
graph_colors = [hsv_to_hex((base_h + i/13.0) % 1.0, s, v) for i in range(13)]

with open('$SOURCEGIT_BASE', 'r') as f:
    theme = json.load(f)
theme['BasicColors']['SystemAccentColor'] = '${accent}'.upper()
theme['BasicColors']['Badge'] = '${accent}'.upper()
theme['GraphColors'] = graph_colors
with open('$SOURCEGIT_THEME', 'w') as f:
    json.dump(theme, f, indent=4)
print('SourceGit theme updated')
EOF

# 8. Patch Ferdium settings (regardless of whether it's running)
FERDIUM_SETTINGS="$HOME/.config/Ferdium/config/settings.json"
if [ -f "$FERDIUM_SETTINGS" ]; then
    jq --arg color "$colorLine" \
        '.accentColor = $color | .progressbarAccentColor = $color' \
        "$FERDIUM_SETTINGS" > /tmp/ferdium-settings.tmp \
        && mv /tmp/ferdium-settings.tmp "$FERDIUM_SETTINGS"
fi

# 9. Restart apps: detect all, kill all at once, wait, launch all at once
# Format: "pgrep_flag|detect_pattern|kill_pattern|launch_cmd|hyprland_window_class"
# Leave window_class empty for apps that don't create Hyprland windows (e.g. tray-only)
declare -A APPS
APPS[dolphin]="x|dolphin|dolphin|dolphin|dolphin"
APPS[zen]="f|zen-bin|zen-bin|zen-browser|zen"
APPS[ferdium]="f|electron.*ferdium-bin|electron.*ferdium-bin|ferdium|"
APPS[sourcegit]="x|sourcegit|sourcegit|sourcegit|sourcegit"

# Collect all running PIDs in one pass
running=()
all_pids=()
for app in "${!APPS[@]}"; do
    IFS='|' read -r flag detect _ _ _ <<< "${APPS[$app]}"
    if [ "$flag" = "f" ]; then
        mapfile -t apids < <(pgrep -f "$detect" 2>/dev/null)
    else
        mapfile -t apids < <(pgrep -x "$detect" 2>/dev/null)
    fi
    if [ ${#apids[@]} -gt 0 ]; then
        running+=("$app")
        all_pids+=("${apids[@]}")
    fi
done

# Kill all PIDs in one syscall
[ ${#all_pids[@]} -gt 0 ] && kill "${all_pids[@]}" 2>/dev/null

# Wait for all to die using kill -0 (fast polling)
if [ ${#all_pids[@]} -gt 0 ]; then
    deadline=$(( $(date +%s) + 5 ))
    while [ $(date +%s) -lt $deadline ]; do
        all_dead=1
        for pid in "${all_pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && all_dead=0 && break
        done
        [ $all_dead -eq 1 ] && break
        sleep 0.05
    done
fi

# Launch all at once
for app in "${running[@]}"; do
    IFS='|' read -r _ _ _ launch _ <<< "${APPS[$app]}"
    $launch >/dev/null 2>&1 &
    disown
done

if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
    # Wait for each windowed app individually
    for app in "${running[@]}"; do
        IFS='|' read -r _ _ _ _ wclass <<< "${APPS[$app]}"
        [ -z "$wclass" ] && continue
        app_deadline=$(( $(date +%s) + 5 ))
        while [ $(date +%s) -lt $app_deadline ]; do
            hyprctl clients -j | python3 -c "
import json,sys
clients=json.load(sys.stdin)
exit(0 if any('$wclass' in c.get('class','').lower() for c in clients) else 1)
" 2>/dev/null && break
            sleep 0.1
        done
    done

    # Restore Hyprland layout state after all restarts
    # (restore script handles returning to saved workspace internally)
    "$HOME/.config/WallpaperChanger/hyprMasterLayoutPreservation.sh" restore
fi