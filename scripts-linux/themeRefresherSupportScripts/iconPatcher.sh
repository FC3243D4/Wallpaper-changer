#!/usr/bin/env bash
# iconPatcher.sh
# Patches icon SVGs in breeze-dark-accent with the accent color.
#
# v2 — merged with gamesIconPatcher.sh. Instead of one hand-written function
# per app, a generic engine scans every .desktop file and resolves an icon:
#
#   1. ICON_OVERRIDES[slug]              — manual override (games-style)
#   2. ${slug}_base_icon.svg             — custom icon matching the app name
#      (searched in $GAME_ICONS first, then $ICONS)
#   3. game detection                    — generic "gaming" icon
#   4. Categories= match                 — generic per-category icon
#   5. application_base_icon.svg         — last-resort catch-all (optional,
#                                          only if the file exists)
#
# Icons that need multi-tone HSV math, PNG recoloring, tray JSON, or system
# theme (breeze) patching keep their dedicated functions below; they run
# BEFORE the engine and register their .desktop files so the engine skips
# them.
#
# Usage: iconPatcher.sh <hex_color> [--dry-run]
#   --dry-run  only run the generic engine in report mode: print
#              NAME -> slug -> icon (reason) for every .desktop file,
#              write nothing. Use this to find the slug keys to put in
#              ICON_OVERRIDES (replaces game_slug.sh for that job).

color="${1,,}"
DRY_RUN=0
[ "${2:-}" = "--dry-run" ] && DRY_RUN=1

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color> [--dry-run]" >&2
    exit 1
fi

accent="#$color"
ICON_DIR="$HOME/.local/share/icons/breeze-dark-accent"
SUPPORT="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"
ICONS="$SUPPORT/svg"
GAME_ICONS="$ICONS/games"                 # drop per-game custom icons here

mkdir -p "$ICON_DIR/apps/16" "$ICON_DIR/apps/22" "$ICON_DIR/apps/24" \
         "$ICON_DIR/apps/32" "$ICON_DIR/apps/44" "$ICON_DIR/apps/48" \
         "$ICON_DIR/apps/64" "$ICON_DIR/apps/scalable" "$GAME_ICONS"

DESKTOP_DIRS=(
    "$HOME/.local/share/applications"
    "/usr/share/applications"
    "/usr/local/share/applications"
    "/var/lib/flatpak/exports/share/applications"
    "$HOME/.local/share/flatpak/exports/share/applications"
)

# Marks a user-dir .desktop file as OUR copy of a system file (created by
# patch_desktop_file to safely edit Icon= without touching root-owned
# files) rather than a genuine user-only entry. See patch_desktop_file and
# cleanup_stale_desktop_overrides below.
DESKTOP_OVERRIDE_MARKER="X-IconPatcherManaged=true"

# Removes marked overrides once the system .desktop file they shadow no
# longer exists anywhere (i.e. the app was uninstalled) — otherwise
# DESKTOP_DIRS listing the user dir first means a stale copy shadows the
# (now-nonexistent) original forever, and things like uninstalled apps
# keep appearing in launchers. Only ever touches marked files; a real
# user-only .desktop (e.g. Steam/Heroic shortcuts, which live solely in
# this directory) is never marked and so is never a candidate here.
# Runs before anything else scans DESKTOP_DIRS, so a removed entry doesn't
# shadow anything for the rest of this same run either.
# Retroactively marks overrides created by earlier runs, before this
# marker system existed. Only marks a file if a system .desktop with the
# same basename still exists today — i.e. it's demonstrably still
# shadowing something real right now, so it's safe to treat as prunable
# once that original eventually disappears. Anything whose basename has
# no system counterpart today is left alone (could be a genuine user-only
# entry like a Steam/Heroic shortcut, or could be already-orphaned from
# before this system existed — either way, there's no longer a safe way
# to tell the difference, so those need a one-time manual check instead).
backfill_desktop_override_markers() {
    local user_dir="$HOME/.local/share/applications"
    [ -d "$user_dir" ] || return 0
    local system_dirs=(
        "/usr/share/applications"
        "/usr/local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
        "$HOME/.local/share/flatpak/exports/share/applications"
    )
    local marked=0
    while IFS= read -r -d '' f; do
        grep -qxF "$DESKTOP_OVERRIDE_MARKER" "$f" 2>/dev/null && continue
        local base found=0
        base=$(basename "$f")
        for dir in "${system_dirs[@]}"; do
            [ -f "$dir/$base" ] && { found=1; break; }
        done
        if [ "$found" -eq 1 ]; then
            echo "$DESKTOP_OVERRIDE_MARKER" >> "$f"
            marked=$((marked + 1))
        fi
    done < <(find "$user_dir" -maxdepth 1 -type f -name "*.desktop" -print0 2>/dev/null)
    [ "$marked" -gt 0 ] && echo "Backfilled override marker on $marked existing .desktop file(s)"
}

# Removes marked overrides once the system .desktop file they shadow no
# longer exists anywhere (i.e. the app was uninstalled) — otherwise
# DESKTOP_DIRS listing the user dir first means a stale copy shadows the
# (now-nonexistent) original forever, and things like uninstalled apps
# keep appearing in launchers. Only ever touches marked files; a real
# user-only .desktop (e.g. Steam/Heroic shortcuts, which live solely in
# this directory) is never marked and so is never a candidate here.
# Runs before anything else scans DESKTOP_DIRS, so a removed entry doesn't
# shadow anything for the rest of this same run either.
cleanup_stale_desktop_overrides() {
    local user_dir="$HOME/.local/share/applications"
    [ -d "$user_dir" ] || return 0
    backfill_desktop_override_markers
    local system_dirs=(
        "/usr/share/applications"
        "/usr/local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
        "$HOME/.local/share/flatpak/exports/share/applications"
    )
    local removed=0
    while IFS= read -r -d '' f; do
        grep -qxF "$DESKTOP_OVERRIDE_MARKER" "$f" 2>/dev/null || continue
        local base found=0
        base=$(basename "$f")
        for dir in "${system_dirs[@]}"; do
            [ -f "$dir/$base" ] && { found=1; break; }
        done
        if [ "$found" -eq 0 ]; then
            rm -f "$f"
            echo "  removed stale override: $base (no longer installed)"
            removed=$((removed + 1))
        fi
    done < <(find "$user_dir" -maxdepth 1 -type f -name "*.desktop" -print0 2>/dev/null)
    if [ "$removed" -gt 0 ]; then
        echo "Cleaned up $removed stale .desktop override(s)"
        update-desktop-database "$user_dir" 2>/dev/null
    fi
}

# .desktop basenames already themed by a dedicated function this run —
# the generic engine skips these. Filled in by patch_desktop_icon.
declare -A HANDLED_DESKTOPS
# Icon names already generated this run (many apps share one generic icon,
# no point recoloring it more than once).
declare -A GENERATED_ICONS

# ---------------------------------------------------------------------------
# Manual overrides — the games-style map, now for everything.
# Key   = slug derived from the .desktop file's Name= (run --dry-run to see
#         the exact slug for every entry on your system).
# Value = icon base name: the engine looks for <value>_base_icon.svg in
#         $GAME_ICONS first, then $ICONS.
# Use this when the normalized slug doesn't match the icon filename
# (punctuation, subtitles, vendor prefixes, shared icons, etc).
# ---------------------------------------------------------------------------
declare -A ICON_OVERRIDES=(
    # -- games (formerly GAME_SLUG_OVERRIDES) --
    ["forza_horizon_6"]="forza"
    ["elden_ring"]="elden_ring"
    ["elden_ring_nightreign"]="elden_ring"
    ["nierautomata"]="nier_automata"
    ["clair_obscur_expedition_33"]="expedition_33"
    ["halo_the_master_chief_collection"]="halo"

    # -- apps whose Name= doesn't slugify to the icon filename --
    ["visual_studio_code"]="vscode"
    ["code"]="vscode"
    ["code_oss"]="vscode"
    ["brave_web_browser"]="brave"
    ["google_chrome"]="chrome"
    ["chromium"]="chrome"
    ["gnu_image_manipulation_program"]="gimp"
    ["onlyoffice_desktop_editors"]="onlyoffice"
    ["obs_studio"]="obs"
    ["displays_settings"]="nwg-displays"
    ["arduino_ide_v2"]="arduino"
    ["ark"]="zip"
    ["btrfs_assistant"]="btrfs"
    ["nativmix"]="nativmix-alt"

    # -- many-to-one shared icons (formerly one function per group) --
    ["advanced_network_configuration"]="network"
    ["avahi_ssh_server_browser"]="network"
    ["avahi_vnc_server_browser"]="network"
    ["avahi_zeroconf_browser"]="network"

    ["mpv_media_player"]="player"
    ["vlc_media_player"]="player"
    ["blackmagic_raw_player"]="player"

    ["davinci_control_panels_setup"]="settings"
    ["grub_customizer"]="settings"
    ["yad_settings"]="settings"
    ["icon_browser"]="settings"
    ["hardware_locality_lstopo"]="settings"
    ["nvtop"]="settings"
    ["qv4l2_test_utility"]="settings"
    ["qvidcap_test_utility"]="settings"
    ["qt_assistant"]="settings"
    ["qt_linguist"]="settings"
    ["qt_d_bus_viewer"]="settings"
    ["scx_manager"]="settings"
    ["uuctl"]="settings"
    ["winetricks"]="settings"
    ["system_settings"]="settings"
    ["conky"]="settings"

    ["blackmagic_raw_speed_test"]="speedtest"

    ["bluetooth_manager"]="bluetooth"

    ["gnome_disks"]="disks"
    ["disks"]="disks"
    ["gparted"]="disks"
    ["kde_partition_manager"]="disks"
    ["filelight"]="disks"

    ["gwenview"]="image_viewer"
    ["image_viewer"]="image_viewer"
    ["loupe"]="image_viewer"
    ["swappy"]="image_viewer"

    ["hp_device_manager"]="hp"
    ["hplip"]="hp"
    ["uiscan"]="hp"
    ["hp_scan"]="hp"

    ["kate"]="text_editor"
    ["kwrite"]="text_editor"
    ["micro"]="text_editor"
    ["text_editor"]="text_editor"
    ["xdvi"]="text_editor"

    ["kcalc"]="calculator"
    ["qalculate"]="calculator"
    ["qalculate_gtk"]="calculator"

    ["kvantum_manager"]="brush"
    ["gtk_settings"]="brush"

    ["kwalletmanager"]="lock"
    ["kde_wallet_manager"]="lock"

    ["manage_printing"]="printer"

    ["lycheeslicer"]="lychee"
    ["lychee_slicer"]="lychee"

    ["nvidia_x_server_settings"]="nvidia"

    ["octopi"]="install"
    ["shelly"]="install"
    ["cachyos_package_installer"]="install"

    ["onedrivegui"]="cloud_storage"

    ["openjdk_java_25_console"]="code"
    ["openjdk_java_25_shell"]="code"
    ["qt_designer"]="code"
    ["cmake"]="code"

    ["rofi"]="launcher"
    ["rofi_theme_selector"]="launcher"

    ["solaar"]="logitech"

    ["spectacle"]="screenshot"

    ["streamcontroller"]="elgato"
    ["opendeck"]="elgato"

    ["pulseaudio_volume_control"]="volume"

    ["xgps"]="location"
    ["xgpsspeed"]="location"

    ["openrgb"]="led"

    ["protontricks"]="gaming"

    ["kde_connect_indicator"]="kde_connect"
    ["kde_connect_sms"]="kde_connect"

    ["sourcegit"]="git"
)

# ---------------------------------------------------------------------------
# Color-token overrides — how to recolor each base icon.
# Key   = icon base name (the resolved value above, or the raw slug).
# Value = space-separated list of tokens to replace with the accent,
#         or "@inject" to add fill="$accent" on the root <svg> tag
#         (for icons with no explicit fill at all).
# Anything not listed here defaults to replacing "currentColor".
# ---------------------------------------------------------------------------
declare -A COLOR_TOKENS=(

)

# ---------------------------------------------------------------------------
# Category fallbacks — checked in order, first match wins, so keep the
# specific desktop categories before the broad ones. Values are icon base
# names ($ICONS/<name>_base_icon.svg must exist for the fallback to apply).
# ---------------------------------------------------------------------------
CATEGORY_FALLBACKS=(
    "TerminalEmulator:terminal"
    "WebBrowser:network"
    "TextEditor:text_editor"
    "Calculator:calculator"
    "Archiving:zip"
    "Compression:zip"
    "IDE:code"
    "Development:code"
    "Photography:image_viewer"
    "Viewer:image_viewer"
    "Graphics:brush"
    "Music:music"
    "Audio:volume"
    "Video:player"
    "AudioVideo:player"
    "Player:player"
    "Office:text_editor"
    "Printing:printer"
    "Security:lock"
    "Network:network"
    "Settings:settings"
    "System:settings"
    "Utility:settings"
)

# Last-resort icon for entries with no custom icon and no matching category.
# Only used if $ICONS/application_base_icon.svg actually exists — otherwise
# unmatched entries are left untouched.
CATCHALL_ICON="application"

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9 -]//g; s/[[:space:]]+/_/g; s/-+/_/g'
}

# Pattern-based slug rewrites that a static map can't express.
normalize_slug() {
    local slug="$1"
    case "$slug" in
        electron_[0-9]*) slug="electron" ;;   # Electron 32, Electron 35, ...
        wine_*)          slug="settings" ;;   # stray Wine helper entries
    esac
    echo "$slug"
}

is_game_desktop_file() {
    local f="$1"
    grep -qE '^Exec=.*(steam://rungameid|lutris:rungame|heroic)' "$f" 2>/dev/null \
        || grep -qiE '^Categories=.*game' "$f" 2>/dev/null
}

# patch_desktop_icon <icon_name> <glob_pattern> [more_patterns...]
# Finds .desktop files matching the given glob(s) in known application dirs.
# If Icon= doesn't already match icon_name, creates/updates a user-level
# override in ~/.local/share/applications (XDG standard: user overrides win
# over system files, no root needed, survives package updates).
# Every matched basename is registered in HANDLED_DESKTOPS so the generic
# engine won't reprocess it.
# patch_desktop_file <icon_name> <exact_path>
# Same override logic, but for one known file — no glob expansion, so
# basenames with spaces (Steam/Heroic game shortcuts) or glob characters
# are handled safely. The generic engine uses this directly.
patch_desktop_file() {
    local icon_name="$1" file="$2"
    [ -f "$file" ] || return 1
    local base
    base="$(basename "$file")"
    HANDLED_DESKTOPS[$base]=1
    local override="$HOME/.local/share/applications/$base"
    local current
    # If a user override already exists, that's what the desktop
    # actually reads — compare against it, not the system file,
    # or every run re-reports (and rewrites) the same change.
    if [ -f "$override" ]; then
        current=$(grep -m1 "^Icon=" "$override" | cut -d= -f2-)
    else
        current=$(grep -m1 "^Icon=" "$file" | cut -d= -f2-)
    fi
    if [ "$current" != "$icon_name" ]; then
        mkdir -p "$HOME/.local/share/applications"
        if [ ! -f "$override" ]; then
            cp "$file" "$override"
            # Marks this as OUR copy of a system file, not a genuine
            # user-only .desktop entry (e.g. Steam/Heroic game shortcuts,
            # which live solely in this directory and must never be
            # pruned). Only files bearing this marker are ever considered
            # for removal by cleanup_stale_desktop_overrides.
            echo "$DESKTOP_OVERRIDE_MARKER" >> "$override"
        fi
        if grep -q "^Icon=" "$override"; then
            sed -i "s|^Icon=.*|Icon=$icon_name|" "$override"
        else
            echo "Icon=$icon_name" >> "$override"
        fi
        echo "  .desktop updated: $base (Icon: ${current:-<none>} -> $icon_name)"
    fi
}

patch_desktop_icon() {
    local icon_name="$1"; shift
    local patterns=("$@")
    local matched=0
    shopt -s nullglob nocaseglob
    for dir in "${DESKTOP_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        for pattern in "${patterns[@]}"; do
            for file in "$dir"/$pattern; do
                [ -f "$file" ] || continue
                matched=1
                patch_desktop_file "$icon_name" "$file"
            done
        done
    done
    shopt -u nullglob nocaseglob
    [ "$matched" -eq 0 ] && echo "  no .desktop file found for $icon_name"
}

# find_base_svg <icon_name> — echoes the path of the matching base SVG,
# preferring per-game icons over the shared pool. Returns 1 if none exists.
find_base_svg() {
    local name="$1"
    if [ -f "$GAME_ICONS/${name}_base_icon.svg" ]; then
        echo "$GAME_ICONS/${name}_base_icon.svg"
    elif [ -f "$ICONS/${name}_base_icon.svg" ]; then
        echo "$ICONS/${name}_base_icon.svg"
    else
        return 1
    fi
}

# colorize_svg <src> <dst> <icon_name>
# Recolors according to COLOR_TOKENS (default: replace currentColor).
patch_svg_color() {
    local src="$1" dst="$2" name="$3"
    local tokens="${COLOR_TOKENS[$name]:-currentColor}"
    python3 - "$src" "$dst" "$accent" "$tokens" << 'PYEOF'
import re
import sys

src, dst, accent, tokens = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(src, "r") as f:
    content = f.read()

if tokens == "@inject":
    # Icon has no explicit fill anywhere — inject one on the root svg tag.
    content = re.sub(r"<svg\b", f'<svg fill="{accent}"', content, count=1)
else:
    for token in tokens.split():
        content = content.replace(token, accent)

with open(dst, "w") as f:
    f.write(content)
PYEOF
}

# ensure_icon <icon_name> — generates the accent-colored SVG in the theme
# dir exactly once per run. Returns 1 if no base SVG exists for the name.
ensure_icon() {
    local name="$1" src
    [ -n "${GENERATED_ICONS[$name]:-}" ] && return 0
    src=$(find_base_svg "$name") || return 1
    patch_svg_color "$src" "$ICON_DIR/apps/scalable/$name.svg" "$name"
    GENERATED_ICONS[$name]=1
}

# category_fallback_icon <desktop_file> — echoes the icon name for the first
# matching Categories= entry (only if its base SVG exists). Returns 1 if no
# category matches.
category_fallback_icon() {
    local f="$1" categories entry cat icon
    categories=$(grep -m1 '^Categories=' "$f" | cut -d= -f2-)
    [ -n "$categories" ] || return 1
    for entry in "${CATEGORY_FALLBACKS[@]}"; do
        cat="${entry%%:*}"
        icon="${entry#*:}"
        if [[ ";$categories;" == *";$cat;"* ]] && [ -f "$ICONS/${icon}_base_icon.svg" ]; then
            echo "$icon"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# The generic engine — formerly ~50 per-app functions + gamesIconPatcher.sh
# ---------------------------------------------------------------------------
patch_all_desktop_icons() {
    local -A seen
    local custom=0 games_fallback=0 by_category=0 catchall=0 untouched=0

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%-40s %-35s %-22s %s\n' "NAME" "SLUG" "ICON" "SOURCE"
        printf '%-40s %-35s %-22s %s\n' "----" "----" "----" "------"
    else
        echo "Scanning .desktop files..."
    fi

    for dir in "${DESKTOP_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' desktop_file; do
            local base name raw_slug slug icon reason
            base=$(basename "$desktop_file")

            # First hit wins; user dir is listed first so local overrides
            # shadow their system originals.
            [ -n "${seen[$base]:-}" ] && continue
            seen[$base]=1

            # Already themed by a dedicated function this run.
            if [ -n "${HANDLED_DESKTOPS[$base]:-}" ]; then
                [ "$DRY_RUN" -eq 1 ] && printf '%-40s %-35s %-22s %s\n' \
                    "($base)" "-" "-" "dedicated function"
                continue
            fi

            name=$(grep -m1 '^Name=' "$desktop_file" | cut -d= -f2-)
            if [ -z "$name" ]; then
                [ "$DRY_RUN" -eq 1 ] && printf '%-40s %-35s %-22s %s\n' \
                    "($base)" "-" "-" "no Name=, skipped"
                continue
            fi

            raw_slug=$(slugify "$name")
            slug=$(normalize_slug "$raw_slug")
            icon="${ICON_OVERRIDES[$slug]:-$slug}"

            if find_base_svg "$icon" >/dev/null; then
                if [ "$icon" != "$slug" ]; then
                    reason="override"
                else
                    reason="custom icon"
                fi
                custom=$((custom + 1))
            elif is_game_desktop_file "$desktop_file"; then
                icon="gaming"
                reason="game fallback"
                games_fallback=$((games_fallback + 1))
            elif icon=$(category_fallback_icon "$desktop_file"); then
                reason="category"
                by_category=$((by_category + 1))
            elif find_base_svg "$CATCHALL_ICON" >/dev/null; then
                icon="$CATCHALL_ICON"
                reason="catch-all"
                catchall=$((catchall + 1))
            else
                [ "$DRY_RUN" -eq 1 ] && printf '%-40s %-35s %-22s %s\n' \
                    "$name" "$slug" "-" "no match, untouched"
                untouched=$((untouched + 1))
                continue
            fi

            if [ "$DRY_RUN" -eq 1 ]; then
                printf '%-40s %-35s %-22s %s\n' "$name" "$slug" "$icon" "$reason"
                continue
            fi

            if ! ensure_icon "$icon"; then
                echo "  '$name' -> base SVG for '$icon' vanished mid-run, skipping"
                continue
            fi
            echo "'$name' -> $icon ($reason)"
            patch_desktop_file "$icon" "$desktop_file"
        done < <(find "$dir" -maxdepth 3 -type f -name "*.desktop" -print0 2>/dev/null)
    done

    echo
    echo "Engine summary: $custom custom/override, $games_fallback game fallback," \
         "$by_category by category, $catchall catch-all, $untouched untouched."
}

# ---------------------------------------------------------------------------
# Full breeze-dark theme pass — recolors every upstream breeze-dark SVG that
# references ColorScheme-Accent or ColorScheme-Highlight (folders, places,
# status/battery/network icons, bookmark stars, category icons, etc.), plus
# ColorScheme-Text specifically within status/devices/actions (breeze's flat
# monochrome "symbolic" tray/status glyphs — wifi, bluetooth, volume,
# security, display, etc. — otherwise show up unthemed). ColorScheme-Text
# elsewhere (mimetypes, generic UI chrome) and semantic Positive/Neutral/
# NegativeText status colors are left untouched — those resolve for free
# via index.theme's Inherits=breeze-dark chain, or carry meaning
# (success/error/warning) that shouldn't be overridden by accent.
#
# Run this BEFORE the dedicated per-app functions and the generic engine,
# so hand-curated Tabler-based app icons always win over anything this
# pass writes for the same path.
# ---------------------------------------------------------------------------
patch_full_breeze_theme() {
    local SRC="/usr/share/icons/breeze-dark"
    [ -d "$SRC" ] || { echo "  breeze-dark not found, skipping full-theme pass"; return 1; }

    # Single python3 process walks + rewrites the whole tree — spawning one
    # interpreter per matched icon (the previous approach) is what made this
    # take minutes; breeze-dark has hundreds of Accent/Highlight icons, and
    # python's ~50-100ms startup cost times hundreds of files adds up fast.
    local dirs_file
    dirs_file=$(mktemp)

    python3 - "$SRC" "$ICON_DIR" "$accent" "$dirs_file" << 'PYEOF'
import os, re, sys

src_root, dst_root, accent, dirs_file = sys.argv[1:5]

# Accent/Highlight: recolored everywhere in the theme, as before.
accent_pattern = re.compile(
    r"(\.ColorScheme-(?:Accent|Highlight)\s*\{[^}]*?color:)\s*#[0-9a-fA-F]{3,8}",
    re.DOTALL,
)

# Text: breeze uses this for its monochrome "symbolic" icons too (status
# tray glyphs — wifi, bluetooth, volume, security, display, etc.), which
# is why they show up unthemed otherwise. Only recolor Text in directories
# where that flat mono style is the norm, so generic UI/mimetype icons
# that rely on Text-for-contrast elsewhere in the theme stay untouched.
text_pattern = re.compile(
    r"(\.ColorScheme-Text\s*\{[^}]*?color:)\s*#[0-9a-fA-F]{3,8}",
    re.DOTALL,
)
TEXT_RECOLOR_DIRS = ("status", "devices", "actions")

count = 0
written_dirs = set()

for dirpath, _, filenames in os.walk(src_root):
    rel_dir = os.path.relpath(dirpath, src_root)
    top_dir = rel_dir.split(os.sep, 1)[0]
    allow_text = top_dir in TEXT_RECOLOR_DIRS

    for fname in filenames:
        if not fname.endswith(".svg"):
            continue
        src_path = os.path.join(dirpath, fname)
        with open(src_path, "r", errors="ignore") as fh:
            content = fh.read()

        has_accent = "ColorScheme-Accent" in content or "ColorScheme-Highlight" in content
        has_text = allow_text and "ColorScheme-Text" in content
        if not has_accent and not has_text:
            continue

        new_content = content
        if has_accent:
            new_content = accent_pattern.sub(r"\g<1> " + accent, new_content)
        if has_text:
            new_content = text_pattern.sub(r"\g<1> " + accent, new_content)

        rel = os.path.relpath(src_path, src_root)
        dst_path = os.path.join(dst_root, rel)
        os.makedirs(os.path.dirname(dst_path), exist_ok=True)
        with open(dst_path, "w") as fh:
            fh.write(new_content)
        written_dirs.add(os.path.dirname(rel))
        count += 1

with open(dirs_file, "w") as fh:
    fh.write("\n".join(sorted(written_dirs)))

print(f"Full breeze-dark pass: {count} icons recolored (accent={accent})")
PYEOF

    if [ -s "$dirs_file" ]; then
        local written_dirs=()
        mapfile -t written_dirs < "$dirs_file"
        update_index_theme_directories "${written_dirs[@]}"
    fi
    rm -f "$dirs_file"
}

# update_index_theme_directories <dir1> [dir2] ...
# Ensures each given directory (relative, e.g. "status/22") has a section
# in breeze-dark-accent/index.theme, copying its Size/Type/Context stanza
# from breeze-dark's own index.theme (source of truth for correctness),
# and keeps the top-level Directories= list in sync. Idempotent — safe to
# call on every run, only ever adds sections, never removes.
update_index_theme_directories() {
    local theme_file="$ICON_DIR/index.theme"
    local src_theme="/usr/share/icons/breeze-dark/index.theme"
    [ -f "$theme_file" ] || { echo "  $theme_file missing, skipping index.theme sync"; return 1; }
    [ -f "$src_theme" ]  || { echo "  breeze-dark/index.theme not found, skipping sync"; return 1; }

    python3 - "$theme_file" "$src_theme" "$@" << 'PYEOF'
import configparser, sys

theme_file, src_theme, *new_dirs = sys.argv[1:]

def load(path):
    cp = configparser.ConfigParser(strict=False)
    cp.optionxform = str  # preserve case
    cp.read(path)
    return cp

local = load(theme_file)
src = load(src_theme)

existing = [d.strip() for d in local["Icon Theme"].get("Directories", "").split(",") if d.strip()]
existing_set = set(existing)

added = []
for d in new_dirs:
    if d in existing_set:
        continue
    if d not in src:
        print(f"  '{d}' has no section in upstream index.theme, skipping")
        continue
    local[d] = dict(src[d])
    existing.append(d)
    existing_set.add(d)
    added.append(d)

local["Icon Theme"]["Directories"] = ",".join(existing)

# Rewrite by hand to control section order (Icon Theme first, as convention expects)
with open(theme_file, "w") as f:
    f.write("[Icon Theme]\n")
    for k, v in local["Icon Theme"].items():
        f.write(f"{k}={v}\n")
    for section in local.sections():
        if section == "Icon Theme":
            continue
        f.write(f"\n[{section}]\n")
        for k, v in local[section].items():
            f.write(f"{k}={v}\n")

if added:
    print(f"  index.theme: added {len(added)} directories: {', '.join(added)}")
else:
    print("  index.theme: no new directories needed")
PYEOF
}

# ===========================================================================
# Dedicated functions — icons that can't be handled by a plain token swap
# (multi-tone HSV math, PNG recoloring, system breeze theme files, tray
# state icons). These run before the engine and register their .desktop
# files in HANDLED_DESKTOPS via patch_desktop_icon.
# ===========================================================================

patch_folder_icons() {
    for size in 16 22 24 32 48 64 96; do
        src="/usr/share/icons/breeze-dark/places/$size/folder.svg"
        dst="$ICON_DIR/places/$size/folder.svg"
        [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
    done
}

# Replace the Places-panel Trash icon (user-trash / user-trash-full)
# outright with the symbolic action icon (trash-empty-symbolic), rather
# than recoloring breeze's own places/user-trash.svg artwork. Uses the
# same ColorScheme-Text token as the status/devices/actions fix above, so
# recolored independently here rather than depending on
# patch_full_breeze_theme having already generated a copy. Vector SVG, so
# one file copied into every size directory renders correctly regardless
# of nominal size.
patch_trash_icon() {
    local src="/usr/share/icons/breeze-dark/actions/24/trash-empty-symbolic.svg"
    if [ ! -f "$src" ]; then
        echo "  trash-empty-symbolic.svg not found, skipping trash icon"
        return 1
    fi
    for size in 16 22 24 32 48 64 96; do
        for name in user-trash user-trash-full; do
            dst="$ICON_DIR/places/$size/$name.svg"
            mkdir -p "$(dirname "$dst")"
            sed "s/ColorScheme-Text { color: #[0-9a-fA-F]*/ColorScheme-Text { color: $accent/g" "$src" > "$dst"
        done
    done
    echo "Trash icon replaced with symbolic version (accent=$accent)"
}

patch_inode_directory_icon() {
    src="/usr/share/icons/breeze-dark/mimetypes/64/inode-directory.svg"
    dst="$ICON_DIR/mimetypes/64/inode-directory.svg"
    [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
}

patch_system_file_manager_icon() {
    for size in 16 22 24 32 48 64; do
        src="/usr/share/icons/breeze-dark/apps/$size/system-file-manager.svg"
        dst="$ICON_DIR/apps/$size/system-file-manager.svg"
        [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
    done
}

patch_preferences_system_icon() {
    for size in 16 32 48; do
        src="/usr/share/icons/breeze-dark/apps/$size/preferences-system.svg"
        dst="$ICON_DIR/apps/$size/preferences-system.svg"
        [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
    done
}

# org.kde.dolphin — patch ColorScheme-Highlight (multiline)
patch_dolphin_icon() {
    if command -v dolphin >/dev/null 2>&1; then
python3 - << EOF
import re
with open("/usr/share/icons/hicolor/scalable/apps/org.kde.dolphin.svg", "r") as f:
    content = f.read()
content = re.sub(
    r"(\.ColorScheme-Highlight\s*\{[^}]*color:)\s*#[0-9a-fA-F]+",
    r"\g<1> $accent",
    content,
    flags=re.DOTALL
)
with open("$ICON_DIR/apps/scalable/org.kde.dolphin.svg", "w") as f:
    f.write(content)
print("Dolphin icon patched")
EOF
        patch_desktop_icon "org.kde.dolphin" "org.kde.dolphin.desktop"
    fi
}

# org.cachyos.hello — replace teal colors with accent + lighter highlight
patch_cachyos_hello_icon() {
    if command -v cachyos-hello >/dev/null 2>&1; then
python3 - << EOF
import colorsys

def hex_to_rgb(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c*2 for c in h)
    return tuple(int(h[i:i+2], 16)/255 for i in (0, 2, 4))

def rgb_to_hex(r, g, b):
    return "#{:02x}{:02x}{:02x}".format(int(r*255), int(g*255), int(b*255))

r, g, b = hex_to_rgb("$accent")
h, s, v = colorsys.rgb_to_hsv(r, g, b)
hr, hg, hb = colorsys.hsv_to_rgb(h, max(0, s - 0.3), min(1, v + 0.25))
highlight = rgb_to_hex(hr, hg, hb)

with open("/usr/share/icons/hicolor/scalable/apps/org.cachyos.hello.svg", "r") as f:
    content = f.read()
for old in ["#008066", "#0fc", "#0a8"]:
    content = content.replace(old, "$accent")
content = content.replace("#0cf", highlight)
with open("$ICON_DIR/apps/scalable/org.cachyos.hello.svg", "w") as f:
    f.write(content)
print(f"CachyOS icon patched (accent=$accent, highlight={highlight})")
EOF
        patch_desktop_icon "org.cachyos.hello" "*cachyos*hello*.desktop" "org.cachyos.hello.desktop"
    fi
}

# CachyOS Kernel Manager — ships PNG-only icons (16/22/32/44px), no scalable
# SVG upstream, so we can't sed-swap hex codes the way patch_cachyos_hello_icon
# does. Artwork is effectively single-hue (a green gradient with anti-aliased
# edges), so ImageMagick's -colorize 100% flattens it to the accent color
# while preserving the alpha/anti-aliasing shape — no HSV shading needed.
patch_cachyos_kernel_manager_icon() {
    if command -v cachyos-kernel-manager >/dev/null 2>&1 && { command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; }; then
        local tool="convert"
        command -v magick >/dev/null 2>&1 && tool="magick"
        local patched=0
        for size in 16 22 32 44; do
            src="/usr/share/icons/hicolor/${size}x${size}/apps/org.cachyos.KernelManager.png"
            dst="$ICON_DIR/apps/$size/cachyos-kernel-manager.png"
            if [ -f "$src" ]; then
                "$tool" "$src" -fill "$accent" -colorize 100% "$dst"
                patched=1
            fi
        done
        if [ "$patched" -eq 1 ]; then
            echo "CachyOS Kernel Manager icon patched"
            patch_desktop_icon "cachyos-kernel-manager" "org.cachyos.KernelManager.desktop" "*cachyos*kernel*manager*.desktop"
        else
            echo "  no CachyOS Kernel Manager icon files found to patch"
        fi
    fi
}

# Tray icon: deliberately NOT accent-colored. Vesktop's tray icon only
# visibly refreshes when the icon is re-selected through its own UI, not
# on file/settings changes from outside — so a plain, static white icon
# (that never needs re-selecting) is more reliable than chasing per-accent
# recoloring here. Requires rsvg-convert (SVG rasterize) and ImageMagick
# (badge compositing). Called from patch_discord_vesktop_icons.
patch_vesktop_tray_icon() {
    local src="$1"
    VESKTOP_SETTINGS="$HOME/.config/vesktop/settings.json"
    if command -v rsvg-convert >/dev/null 2>&1 && [ -f "$VESKTOP_SETTINGS" ]; then
        TRAY_DIR="$SUPPORT/tray-icons"
        mkdir -p "$TRAY_DIR"

        white_svg="$(mktemp --suffix=.svg)"
        sed "s/#000000/#ffffff/g" "$src" > "$white_svg"

        tray_png="$TRAY_DIR/vesktop-tray.png"
        rsvg-convert -w 256 -h 256 "$white_svg" -o "$tray_png"
        rm -f "$white_svg"
        echo "Vesktop tray icon generated (white)"

        # Unread-state variant: same white icon with a red notification
        # dot composited in the bottom-right corner.
        tray_png_unread="$TRAY_DIR/vesktop-tray-unread.png"
        if command -v magick >/dev/null 2>&1; then
            magick "$tray_png" -fill "#ed4245" -stroke none \
                -draw "circle 200,56 200,16" "$tray_png_unread"
            echo "Vesktop tray icon (unread/red-dot) generated"
        elif command -v convert >/dev/null 2>&1; then
            convert "$tray_png" -fill "#ed4245" -stroke none \
                -draw "circle 200,56 200,16" "$tray_png_unread"
            echo "Vesktop tray icon (unread/red-dot) generated"
        else
            echo "  ImageMagick not found — skipping unread-state tray icon"
        fi

        python3 - "$VESKTOP_SETTINGS" "$tray_png" << 'EOF'
import json
import sys

settings_path, tray_png = sys.argv[1], sys.argv[2]
with open(settings_path, "r") as f:
    data = json.load(f)

if data.get("trayIconPath") != tray_png:
    data["trayIconPath"] = tray_png
    with open(settings_path, "w") as f:
        json.dump(data, f, indent=4)
    print("  trayIconPath updated (re-select it once in Vesktop's tray icon")
    print("  picker to force a visual refresh — see prior troubleshooting)")
EOF
    elif ! command -v rsvg-convert >/dev/null 2>&1; then
        echo "  rsvg-convert not found — skipping Vesktop tray icon (install librsvg for this)"
    fi
}

# Discord/Vesktop share one base icon, and Vesktop additionally needs the
# tray-state PNGs above — too entangled for the generic engine.
patch_discord_vesktop_icons() {
    src="$ICONS/discord_base_icon.svg"
    if [ -f "$src" ]; then
        if command -v discord >/dev/null 2>&1; then
            sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/discord.svg"
            echo "Discord icon patched"
            patch_desktop_icon "discord" "discord.desktop" "com.discordapp.Discord.desktop"
        fi
        if command -v vesktop >/dev/null 2>&1; then
            sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/vesktop.svg"
            echo "Vesktop icon patched"
            patch_desktop_icon "vesktop" "vesktop.desktop" "*vesktop*.desktop"
            patch_vesktop_tray_icon "$src"
        fi
    fi
}

# Nativmix icon — three-tone
patch_nativmix_icon() {
    src="$ICONS/nativmix_base_icon.svg"
    if [ -f "$src" ] && command -v nativmix >/dev/null 2>&1; then
        python3 - << EOF
import colorsys

def hex_to_hsv(h):
    h = h.lstrip("#")
    r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(1,s), min(1,v))
    return "#{:02x}{:02x}{:02x}".format(int(r*255), int(g*255), int(b*255))

base_h, base_s, base_v = hex_to_hsv("$color")
background = hsv_to_hex(base_h, base_s, base_v)
tracks     = hsv_to_hex(base_h, base_s, max(0, base_v - 0.15))
knobs      = hsv_to_hex(base_h, max(0, base_s - 0.35), min(1, base_v + 0.3))

with open("$src", "r") as f:
    svg = f.read()
svg = svg.replace("#8c8c8c", background)
svg = svg.replace("#282828", tracks)
svg = svg.replace("#dcdcdc", knobs)

with open("$ICON_DIR/apps/scalable/nativmix.svg", "w") as f:
    f.write(svg)
print(f"Nativmix icon patched (bg={background}, tracks={tracks}, knobs={knobs})")
EOF
        patch_desktop_icon "nativmix" "nativmix.desktop" "*nativmix*.desktop"
    fi
}

# OrcaSlicer icon — three-tone: the two near-black shapes collapse to one
# accent-tinted dark shade, the brand teal maps to full accent, and white
# is left untouched as a highlight.
patch_orcaslicer_icon() {
    src="$ICONS/orcaslicer_base_icon.svg"
    if [ -f "$src" ] && command -v orca-slicer >/dev/null 2>&1; then
        python3 - << EOF
import colorsys

def hex_to_hsv(h):
    h = h.lstrip("#")
    r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(1,s), min(1,v))
    return "#{:02x}{:02x}{:02x}".format(int(r*255), int(g*255), int(b*255))

base_h, base_s, base_v = hex_to_hsv("$color")
dark = hsv_to_hex(base_h, base_s, 0.16)
teal = "$accent"

with open("$src", "r") as f:
    svg = f.read()
svg = svg.replace("#292826", dark)
svg = svg.replace("#262523", dark)
svg = svg.replace("#009789", teal)

with open("$ICON_DIR/apps/scalable/orcaslicer.svg", "w") as f:
    f.write(svg)
print(f"OrcaSlicer icon patched (dark={dark}, teal={teal})")
EOF
        patch_desktop_icon "orcaslicer" "orca-slicer.desktop" "*orcaslicer*.desktop" "*orca-slicer*.desktop"
    fi
}

# Conky logomark — multi-tone + embedded raster retinting
patch_conky_icon() {
    src="$ICONS/conky_base_icon.svg"
    if [ -f "$src" ] && command -v conky >/dev/null 2>&1; then
        python3 - << EOF
import colorsys, re, base64, io

def hex_to_hsv(h):
    h = h.lstrip("#")
    r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(1,s), min(1,v))
    return "#{:02x}{:02x}{:02x}".format(int(r*255), int(g*255), int(b*255))

base_h, base_s, base_v = hex_to_hsv("$color")
dark   = hsv_to_hex(base_h, base_s, max(0, base_v - 0.15))
darker = hsv_to_hex(base_h, base_s, max(0, base_v - 0.35))
light  = hsv_to_hex(base_h, max(0, base_s - 0.35), min(1, base_v + 0.25))
mid    = "$accent"

with open("$src", "r") as f:
    svg = f.read()

svg = svg.replace("#B19DCB", light)   # st0 — background quad
svg = svg.replace("#666699", mid)     # st1 — blue-violet bars (40% opacity)
svg = svg.replace("#583494", dark)    # st2 — main solid "C" ring
svg = svg.replace("#3D296D", darker)  # st3 — dark accent rect (40% opacity)

try:
    from PIL import Image, ImageOps
    m = re.search(r'xlink:href="data:image/png;base64,([^"]+)"', svg)
    if m:
        png_bytes = base64.b64decode(m.group(1))
        im = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
        r, g, b, a = im.split()
        gray = Image.merge("RGB", (r, g, b)).convert("L")
        tinted = ImageOps.colorize(gray, black="#000000", white=mid).convert("RGBA")
        tinted.putalpha(a)
        buf = io.BytesIO()
        tinted.save(buf, format="PNG")
        new_b64 = base64.b64encode(buf.getvalue()).decode()
        svg = svg[:m.start(1)] + new_b64 + svg[m.end(1):]
        print("  embedded raster retinted")
    else:
        print("  no embedded raster found (unexpected)")
except ImportError:
    print("  python3-pillow not found — embedded raster left unrecolored")

with open("$ICON_DIR/apps/scalable/conky.svg", "w") as f:
    f.write(svg)
print(f"Conky icon patched (dark={dark}, mid={mid}, light={light}, darker={darker})")
EOF

        patch_desktop_icon "conky" "conky.desktop" "*conky*.desktop"
    fi
}

# Wlogout icons — hovered/standard pairs with a dimmed derived shade,
# written to wlogout's own config dir rather than the icon theme.
patch_wlogout_icons() {
    wlogout_icons_dir="$HOME/.config/wlogout/icons"
    if command -v wlogout >/dev/null 2>&1; then
        mkdir -p "$wlogout_icons_dir"

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
        sed "s/currentColor/$accent/g"   "$ICONS/lock_base_icon.svg"     > "$wlogout_icons_dir/lock-hovered.svg"
        sed "s/currentColor/$accent/g"   "$ICONS/reboot_base_icon.svg"   > "$wlogout_icons_dir/reboot-hovered.svg"
        sed "s/currentColor/$accent/g"   "$ICONS/power_base_icon.svg"    > "$wlogout_icons_dir/power-hovered.svg"
        sed "s/currentColor/$accent/g"   "$ICONS/logout_base_icon.svg"   > "$wlogout_icons_dir/logout-hovered.svg"
        sed "s/currentColor/$accent/g"   "$ICONS/sleep_base_icon.svg"    > "$wlogout_icons_dir/sleep-hovered.svg"
        sed "s/currentColor/$accent/g"   "$ICONS/suspend_base_icon.svg"  > "$wlogout_icons_dir/suspend-hovered.svg"

        # Standard (dimmed)
        sed "s/currentColor/$standard/g" "$ICONS/lock_base_icon.svg"     > "$wlogout_icons_dir/lock-standard.svg"
        sed "s/currentColor/$standard/g" "$ICONS/reboot_base_icon.svg"   > "$wlogout_icons_dir/reboot-standard.svg"
        sed "s/currentColor/$standard/g" "$ICONS/power_base_icon.svg"    > "$wlogout_icons_dir/power-standard.svg"
        sed "s/currentColor/$standard/g" "$ICONS/logout_base_icon.svg"   > "$wlogout_icons_dir/logout-standard.svg"
        sed "s/currentColor/$standard/g" "$ICONS/sleep_base_icon.svg"    > "$wlogout_icons_dir/sleep-standard.svg"
        sed "s/currentColor/$standard/g" "$ICONS/suspend_base_icon.svg"  > "$wlogout_icons_dir/suspend-standard.svg"

        echo "Wlogout icons patched (standard=$standard, hovered=$accent)"
    fi
}

# Swaync icons — written to swaync's config dir, plus fixed-red error/note
patch_osd_icons() {
    local swaync_icons_dir="$HOME/.config/swaync/icons"
    local notif_red="#e74c3c"  # adjust to taste — not accent-derived, always red
    if command -v swaync >/dev/null 2>&1; then
        mkdir -p "$swaync_icons_dir"

        declare -A osd_icons=(
            [microphone]="microphone"
            [microphone-mute]="microphone-mute"
            [music]="music"
            [picture]="picture"
            [timer]="timer"
            [volume-high]="volume-high"
            [volume-mid]="volume-mid"
            [volume-low]="volume-low"
            [volume-mute]="volume-mute"
            [brightness-20]="brightness-20"
            [brightness-40]="brightness-40"
            [brightness-60]="brightness-60"
            [brightness-80]="brightness-80"
            [brightness-100]="brightness-100"
            [ok]="ok"
            [wallpaper_changer]="wallpaper_changer"
        )

        local patched=0
        for out_name in "${!osd_icons[@]}"; do
            src="$ICONS/${osd_icons[$out_name]}_base_icon.svg"
            if [ -f "$src" ]; then
                sed -e "s/currentColor/$accent/g" "$src" > "$swaync_icons_dir/${out_name}.svg"
                patched=$((patched + 1))
            fi
        done

        # Error/note icons: always red, independent of the accent color
        for out_name in error note; do
            src="$ICONS/${out_name}_base_icon.svg"
            if [ -f "$src" ]; then
                sed "s/currentColor/$notif_red/g" "$src" > "$swaync_icons_dir/${out_name}.svg"
                patched=$((patched + 1))
            fi
        done

        if [ "$patched" -gt 0 ]; then
            echo "OSD icons patched ($patched/16)"
        else
            echo "  no OSD base icons found to patch"
        fi
    fi
}

cleanup_icon_cache() {
    rm -f "$HOME/.cache/icon-cache.kcache"
    kbuildsycoca6 --noincremental 2>/dev/null
}

# ---- Run everything, in order ----
if [ "$DRY_RUN" -eq 1 ]; then
    echo "(dry run: dedicated functions are skipped, nothing is written)"
    echo
    patch_all_desktop_icons
    exit 0
fi

# Prune stale overrides before anything else scans DESKTOP_DIRS, so a
# removed entry doesn't shadow a nonexistent original for the rest of
# this run either.
cleanup_stale_desktop_overrides

# Full breeze-dark theme pass first — recolors every accent/highlight icon
# across the whole upstream theme. Dedicated + engine passes below write
# on top of this, so hand-curated app icons still take priority.
patch_full_breeze_theme

# Dedicated functions next, so the engine knows what's already handled
patch_folder_icons
patch_trash_icon
patch_inode_directory_icon
patch_system_file_manager_icon
patch_preferences_system_icon
patch_dolphin_icon
patch_cachyos_hello_icon
#patch_cachyos_kernel_manager_icon
patch_discord_vesktop_icons
#patch_nativmix_icon
patch_orcaslicer_icon
#patch_conky_icon

# The generic engine — everything else, games included
patch_all_desktop_icons

# Non-.desktop icon sets
patch_wlogout_icons
patch_osd_icons

# Tray icons — split into its own file, see trayIconPatcher.sh
"$SUPPORT/trayIconPatcher.sh" "$color"

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null

cleanup_icon_cache

echo "Icons patched with $accent"