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

# Symbolic (ColorScheme-Text) icons specifically use matugen's resolved
# primary color instead of the raw wallpaper-sampled seed — matching
# tray icons and waybar text, since these icons show up right next to
# both (Solaar, NetworkManager, the trash icon, etc.) and any mismatch is
# just as visible there. Everything using ColorScheme-Accent/Highlight
# (folders, places, and the rest of the theme) keeps using the raw seed
# $accent, unaffected. Falls back to $accent if the rendered file isn't
# found, so this degrades to the previous behavior rather than failing.
#
# NOTE: since migrating the waybar template to InioX/matugen-themes, the
# rendered file moved from .config/waybar/matugen/colors-waybar.css to
# .config/waybar/colors.css, and the role once called "color4" (raw
# colors.primary.default.hex) is now just named "primary" — same value,
# new name.
symbolic_accent="$accent"
WAYBAR_COLORS_RENDERED="$HOME/.config/waybar/colors.css"
if [ -f "$WAYBAR_COLORS_RENDERED" ]; then
    resolved_primary=$(grep -m1 -oP '@define-color\s+primary\s+\K#[0-9a-fA-F]{6}' "$WAYBAR_COLORS_RENDERED")
    [ -n "$resolved_primary" ] && symbolic_accent="$resolved_primary"
fi

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
            if [ -w "$f" ]; then
                echo "$DESKTOP_OVERRIDE_MARKER" >> "$f"
                marked=$((marked + 1))
            else
                echo "  skipping $base (not writable — likely created by something else with elevated privileges)"
            fi
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
    ["orcaslicer"]="orcaslicer-alt"
    ["raspberry_pi_imager"]="raspberry-pi"
    ["intellij_idea_community_edition"]="intellij-idea"
    ["youtube_music_desktop_app"]="music"

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
        if [ -f "$override" ] && [ ! -w "$override" ]; then
            echo "  skipping $base (existing override not writable — likely created by something else with elevated privileges)"
            return 1
        fi
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

    if [ "$tokens" = "@inject" ]; then
        # Icon has no explicit fill anywhere — inject one on the root svg
        # tag. "0,/<svg/" (GNU sed) matches only the first occurrence in
        # the whole file, not just the first line, same as Python's
        # re.sub(..., count=1) this replaced.
        sed "0,/<svg/{s//<svg fill=\"$accent\"/}" "$src" > "$dst"
    else
        # Space-separated token list (usually just "currentColor") — one
        # -e per token, all applied in a single sed invocation. "|" as
        # delimiter avoids collision with "/" that can appear in SVG path
        # data if a token pattern ever needs to be that specific.
        local sed_args=()
        for token in $tokens; do
            sed_args+=(-e "s|$token|$accent|g")
        done
        sed "${sed_args[@]}" "$src" > "$dst"
    fi
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
    # The scanning/decision phase (slugify, category fallback, game
    # detection, cross-directory dedup) used to spawn grep/cut/tr/sed per
    # .desktop file — for a few hundred files, mostly just to decide
    # nothing needs to happen to ~90% of them, that's 1500+ subprocess
    # forks before any actual writing even starts. Doing that part as one
    # Python pass instead (in-process string ops, no forking) is the
    # single biggest win in this whole script. The actual writes
    # (ensure_icon/patch_desktop_file) stay in bash below, unchanged —
    # only run for files that actually need something written, same as
    # before. Validated against the original bash logic via a side-by-side
    # test harness covering overrides, category fallback, both
    # game-detection paths, catchall, untouched, no-Name, cross-directory
    # dedup, electron/wine slug normalization, and special characters in
    # app names — byte-for-byte identical decisions on every case tested.
    local icon_overrides_file category_fallbacks_file handled_file matches_file
    icon_overrides_file=$(mktemp)
    category_fallbacks_file=$(mktemp)
    handled_file=$(mktemp)
    matches_file=$(mktemp)

    local k
    for k in "${!ICON_OVERRIDES[@]}"; do
        printf '%s\t%s\n' "$k" "${ICON_OVERRIDES[$k]}"
    done > "$icon_overrides_file"

    local entry
    for entry in "${CATEGORY_FALLBACKS[@]}"; do
        printf '%s\n' "$entry"
    done > "$category_fallbacks_file"

    for k in "${!HANDLED_DESKTOPS[@]}"; do
        printf '%s\n' "$k"
    done > "$handled_file"

    [ "$DRY_RUN" -eq 0 ] && echo "Scanning .desktop files..."

    python3 - "$icon_overrides_file" "$category_fallbacks_file" "$handled_file" \
              "$GAME_ICONS" "$ICONS" "$CATCHALL_ICON" "$DRY_RUN" "$matches_file" \
              "${DESKTOP_DIRS[@]}" << 'PYEOF'
import os, re, sys

icon_overrides_file, category_fallbacks_file, handled_file, game_icons_dir, icons_dir, catchall_icon, dry_run, matches_file = sys.argv[1:9]
desktop_dirs = sys.argv[9:]
dry_run = dry_run == "1"

icon_overrides = {}
with open(icon_overrides_file) as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        k, v = line.split("\t", 1)
        icon_overrides[k] = v

category_fallbacks = []
with open(category_fallbacks_file) as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        cat, icon = line.split(":", 1)
        category_fallbacks.append((cat, icon))

handled = set()
with open(handled_file) as f:
    for line in f:
        line = line.rstrip("\n")
        if line:
            handled.add(line)


def slugify(name):
    s = name.lower()
    s = re.sub(r"[^a-z0-9 \-]", "", s)
    s = re.sub(r"\s+", "_", s)
    s = re.sub(r"-+", "_", s)
    return s


def normalize_slug(slug):
    if re.match(r"^electron_[0-9]", slug):
        return "electron"
    if slug.startswith("wine_"):
        return "settings"
    return slug


_base_svg_cache = {}


def find_base_svg(name):
    if name in _base_svg_cache:
        return _base_svg_cache[name]
    p1 = os.path.join(game_icons_dir, f"{name}_base_icon.svg")
    p2 = os.path.join(icons_dir, f"{name}_base_icon.svg")
    result = p1 if os.path.isfile(p1) else (p2 if os.path.isfile(p2) else None)
    _base_svg_cache[name] = result
    return result


def is_game_desktop_file(content):
    if re.search(r"^Exec=.*(steam://rungameid|lutris:rungame|heroic)", content, re.M):
        return True
    if re.search(r"^Categories=.*game", content, re.M | re.I):
        return True
    return False


def get_field(content, field):
    m = re.search(rf"^{field}=(.*)$", content, re.M)
    return m.group(1) if m else None


def category_fallback_icon(categories):
    if not categories:
        return None
    padded = f";{categories};"
    for cat, icon in category_fallbacks:
        if f";{cat};" in padded and find_base_svg(icon):
            return icon
    return None


seen = set()
custom = games_fallback = by_category = catchall = untouched = 0
dry_lines = []
matches = []

for d in desktop_dirs:
    if not os.path.isdir(d):
        continue
    d_norm = os.path.normpath(d)
    for root, dirs, files in os.walk(d_norm):
        rel = os.path.relpath(root, d_norm)
        depth = 0 if rel == "." else rel.count(os.sep) + 1
        if depth >= 3:
            dirs[:] = []

        for fname in sorted(files):
            if not fname.endswith(".desktop"):
                continue
            desktop_file = os.path.join(root, fname)
            base = fname

            if base in seen:
                continue
            seen.add(base)

            if base in handled:
                if dry_run:
                    dry_lines.append((f"({base})", "-", "-", "dedicated function"))
                continue

            try:
                with open(desktop_file, "r", errors="ignore") as fh:
                    content = fh.read()
            except OSError:
                continue

            name = get_field(content, "Name")
            if not name:
                if dry_run:
                    dry_lines.append((f"({base})", "-", "-", "no Name=, skipped"))
                continue

            raw_slug = slugify(name)
            slug = normalize_slug(raw_slug)
            icon = icon_overrides.get(slug, slug)

            if find_base_svg(icon):
                reason = "override" if icon != slug else "custom icon"
                custom += 1
            elif is_game_desktop_file(content):
                icon = "gaming"
                reason = "game fallback"
                games_fallback += 1
            else:
                categories = get_field(content, "Categories")
                fb_icon = category_fallback_icon(categories)
                if fb_icon:
                    icon = fb_icon
                    reason = "category"
                    by_category += 1
                elif find_base_svg(catchall_icon):
                    icon = catchall_icon
                    reason = "catch-all"
                    catchall += 1
                else:
                    if dry_run:
                        dry_lines.append((name, slug, "-", "no match, untouched"))
                    untouched += 1
                    continue

            if dry_run:
                dry_lines.append((name, slug, icon, reason))
            else:
                matches.append((desktop_file, icon, name, reason))

if dry_run:
    print(f"{'NAME':<40} {'SLUG':<35} {'ICON':<22} SOURCE")
    print(f"{'----':<40} {'----':<35} {'----':<22} ------")
    for name, slug, icon, reason in dry_lines:
        print(f"{name:<40} {slug:<35} {icon:<22} {reason}")
    print()
    print(
        f"Engine summary: {custom} custom/override, {games_fallback} game fallback, "
        f"{by_category} by category, {catchall} catch-all, {untouched} untouched."
    )
else:
    with open(matches_file, "w") as f:
        for desktop_file, icon, name, reason in matches:
            f.write(f"{desktop_file}\t{icon}\t{name}\t{reason}\n")
    print(
        f"Engine summary: {custom} custom/override, {games_fallback} game fallback, "
        f"{by_category} by category, {catchall} catch-all, {untouched} untouched."
    )
PYEOF

    if [ "$DRY_RUN" -eq 1 ]; then
        rm -f "$icon_overrides_file" "$category_fallbacks_file" "$handled_file" "$matches_file"
        return 0
    fi

    # Actual writes — same functions, same behavior as before. Only runs
    # for files the Python pass decided actually need something written.
    local desktop_file icon name reason
    while IFS=$'\t' read -r desktop_file icon name reason; do
        [ -z "$desktop_file" ] && continue
        if ! ensure_icon "$icon"; then
            echo "  '$name' -> base SVG for '$icon' vanished mid-run, skipping"
            continue
        fi
        echo "'$name' -> $icon ($reason)"
        patch_desktop_file "$icon" "$desktop_file"
    done < "$matches_file"

    rm -f "$icon_overrides_file" "$category_fallbacks_file" "$handled_file" "$matches_file"
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
# On a completely fresh machine, breeze-dark-accent may not exist as a
# theme at all yet — nothing before this point ever creates its
# index.theme from scratch (update_index_theme_directories below only
# ever appends sections to one that already exists). Without this file,
# and specifically its Inherits=breeze-dark line, breeze-dark-accent isn't
# a valid/complete icon theme: anything this pipeline hasn't explicitly
# recolored has no fallback to resolve through at all, which is why a
# fresh install can show "no icon" for almost everything rather than just
# the handful of apps this pipeline actually themes.
ensure_icon_theme_index() {
    local theme_file="$ICON_DIR/index.theme"
    [ -f "$theme_file" ] && return 0

    mkdir -p "$ICON_DIR"
    cat > "$theme_file" << 'EOF'
[Icon Theme]
Name=Breeze Dark Accent
Comment=Breeze Dark with dynamic accent color theming
Inherits=breeze-dark
Directories=
EOF
    echo "  breeze-dark-accent/index.theme created (was missing — fresh install bootstrap)"
}

# Registers the directories THIS pipeline's own custom/override icons get
# written into (see the mkdir -p at the top of this script) — apps/scalable
# above all, since that's where ensure_icon() puts every "custom icon" /
# "override" / "category" / "catch-all" app icon (the majority of the
# engine's output). update_index_theme_directories only ever copies
# stanzas FROM breeze-dark's own index.theme, for directories the
# breeze-mirror pass happened to write to this run — it has no connection
# to ensure_icon's output at all, so apps/scalable can go permanently
# unregistered on a freshly bootstrapped index.theme (files present and
# correctly colored on disk, but invisible to icon-theme lookup, since a
# directory not listed in Directories= doesn't exist as far as GTK/Qt icon
# resolution is concerned). Hand-written stanzas here rather than copied
# from breeze-dark, since breeze-dark doesn't necessarily define matching
# sections for some of these (e.g. size 44 is nonstandard).
ensure_app_icon_directories() {
    local theme_file="$ICON_DIR/index.theme"
    [ -f "$theme_file" ] || return 1

    python3 - "$theme_file" << 'PYEOF'
import configparser, sys

theme_file = sys.argv[1]

APP_DIR_STANZAS = {
    "apps/16":       {"Size": "16", "Context": "Applications", "Type": "Fixed"},
    "apps/22":       {"Size": "22", "Context": "Applications", "Type": "Fixed"},
    "apps/24":       {"Size": "24", "Context": "Applications", "Type": "Fixed"},
    "apps/32":       {"Size": "32", "Context": "Applications", "Type": "Fixed"},
    "apps/44":       {"Size": "44", "Context": "Applications", "Type": "Fixed"},
    "apps/48":       {"Size": "48", "Context": "Applications", "Type": "Fixed"},
    "apps/64":       {"Size": "64", "Context": "Applications", "Type": "Fixed"},
    "apps/scalable": {"Size": "48", "MinSize": "1", "MaxSize": "512",
                       "Context": "Applications", "Type": "Scalable"},
}

cp = configparser.ConfigParser(strict=False)
cp.optionxform = str
cp.read(theme_file)

existing = [d.strip() for d in cp["Icon Theme"].get("Directories", "").split(",") if d.strip()]
existing_set = set(existing)

added = []
for d, stanza in APP_DIR_STANZAS.items():
    if d not in existing_set:
        existing.append(d)
        existing_set.add(d)
        added.append(d)
    cp[d] = stanza  # always (re)assert contents — cheap, idempotent

cp["Icon Theme"]["Directories"] = ",".join(existing)

with open(theme_file, "w") as f:
    f.write("[Icon Theme]\n")
    for k, v in cp["Icon Theme"].items():
        f.write(f"{k}={v}\n")
    for section in cp.sections():
        if section == "Icon Theme":
            continue
        f.write(f"\n[{section}]\n")
        for k, v in cp[section].items():
            f.write(f"{k}={v}\n")

if added:
    print(f"  index.theme: registered app-icon directories: {', '.join(added)}")
PYEOF
}

patch_full_breeze_theme() {
    local SRC="/usr/share/icons/breeze-dark"
    [ -d "$SRC" ] || { echo "  breeze-dark not found, skipping full-theme pass"; return 1; }

    ensure_icon_theme_index
    ensure_app_icon_directories

    # Multiprocessing pool — each SVG's read/regex/write is fully
    # independent of every other one (no shared state between files, only
    # the final written_dirs set needs merging afterward), so this is a
    # clean fit for parallelizing across cores rather than walking the
    # whole tree in a single process. Collecting the file list itself
    # stays single-threaded since that part is cheap (just os.walk, no
    # file I/O yet) — only the actual per-file work is farmed out.
    local dirs_file
    dirs_file=$(mktemp)

    python3 - "$SRC" "$ICON_DIR" "$accent" "$dirs_file" "$symbolic_accent" << 'PYEOF'
import multiprocessing as mp
import os, re, sys

src_root, dst_root, accent, dirs_file, symbolic_accent = sys.argv[1:6]

TEXT_RECOLOR_DIRS = ("status", "devices", "actions")

_accent_pattern = None
_text_pattern = None

def _init_worker(a, s):
    global _accent, _symbolic, _accent_pattern, _text_pattern
    _accent, _symbolic = a, s
    _accent_pattern = re.compile(
        r"(\.ColorScheme-(?:Accent|Highlight)\s*\{[^}]*?color:)\s*#[0-9a-fA-F]{3,8}",
        re.DOTALL,
    )
    _text_pattern = re.compile(
        r"(\.ColorScheme-Text\s*\{[^}]*?color:)\s*#[0-9a-fA-F]{3,8}",
        re.DOTALL,
    )

def _process_one(args):
    src_path, dst_path, allow_text = args
    with open(src_path, "r", errors="ignore") as fh:
        content = fh.read()

    has_accent = "ColorScheme-Accent" in content or "ColorScheme-Highlight" in content
    has_text = allow_text and "ColorScheme-Text" in content
    if not has_accent and not has_text:
        return None

    new_content = content
    if has_accent:
        new_content = _accent_pattern.sub(r"\g<1> " + _accent, new_content)
    if has_text:
        new_content = _text_pattern.sub(r"\g<1> " + _symbolic, new_content)

    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    with open(dst_path, "w") as fh:
        fh.write(new_content)
    return os.path.dirname(os.path.relpath(dst_path, dst_root))

# Collecting the task list is cheap (no file reads yet) — stays serial.
tasks = []
for dirpath, _, filenames in os.walk(src_root):
    rel_dir = os.path.relpath(dirpath, src_root)
    top_dir = rel_dir.split(os.sep, 1)[0]
    allow_text = top_dir in TEXT_RECOLOR_DIRS
    for fname in filenames:
        if not fname.endswith(".svg"):
            continue
        src_path = os.path.join(dirpath, fname)
        rel = os.path.relpath(src_path, src_root)
        dst_path = os.path.join(dst_root, rel)
        tasks.append((src_path, dst_path, allow_text))

count = 0
written_dirs = set()

worker_count = max(1, (os.cpu_count() or 4) // 2)
# Explicitly force "fork" rather than relying on Python's current default
# start method. forkserver/spawn need to re-import the main script from a
# real file path to set up worker processes — impossible here since this
# whole thing runs via `python3 - <<PYEOF` fed through stdin, with no file
# on disk to re-import. fork just duplicates the already-running process
# in memory instead, so it works regardless of what Python's default is
# on a given system/version.
ctx = mp.get_context("fork")
with ctx.Pool(processes=worker_count, initializer=_init_worker, initargs=(accent, symbolic_accent)) as pool:
    for result in pool.imap_unordered(_process_one, tasks, chunksize=32):
        if result is not None:
            written_dirs.add(result)
            count += 1

with open(dirs_file, "w") as fh:
    fh.write("\n".join(sorted(written_dirs)))

print(f"Full breeze-dark pass: {count} icons recolored across {worker_count} workers (accent={accent}, symbolic={symbolic_accent})")
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
            sed "s/ColorScheme-Text { color: #[0-9a-fA-F]*/ColorScheme-Text { color: $symbolic_accent/g" "$src" > "$dst"
        done
    done
    echo "Trash icon replaced with symbolic version (symbolic=$symbolic_accent)"
}

# Dolphin's Places-panel entry for a KDE Connect device is a manually
# created bookmark (kdeconnectd writes it into user-places.xbel), not a
# .desktop-driven app icon — and its bookmark:icon name is "kdeconnect"
# (no underscore), a different name than the "kde_connect" the engine
# already generates via ICON_OVERRIDES for the app's own .desktop entries.
# Exact-match icon lookup means that one-character difference is enough to
# miss entirely. Same artwork, just also written under the name Dolphin
# actually asks for here. Uses symbolic_accent (matugen's primary) rather than the
# raw seed accent, since this sits in the Places panel alongside other
# device/status entries rather than functioning as a standalone app icon.
patch_kdeconnect_places_icon() {
    local src="$ICONS/kde_connect_base_icon.svg"
    if [ ! -f "$src" ]; then
        echo "  kde_connect_base_icon.svg not found, skipping KDE Connect places icon"
        return 1
    fi
    local dst="$ICON_DIR/apps/scalable/kdeconnect.svg"
    sed "s/currentColor/$symbolic_accent/g" "$src" > "$dst"
    echo "KDE Connect places-panel icon patched (symbolic=$symbolic_accent)"
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

# time_step <label> <command...> — runs the given command, prints its
# wall-clock time to stderr afterward. awk instead of bc for the float
# subtraction so this doesn't need an extra package installed. Works for
# both function calls and plain external commands (e.g. the
# trayIconPatcher.sh invocation and update-desktop-database below).
time_step() {
    local label="$1"; shift
    local start end
    start=$(date +%s.%N)
    "$@"
    end=$(date +%s.%N)
    awk -v s="$start" -v e="$end" -v l="$label" \
        'BEGIN { printf "[TIMING] [%7.3fs] %s\n", e - s, l }' >&2
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
time_step "cleanup_stale_desktop_overrides" cleanup_stale_desktop_overrides

# Full breeze-dark theme pass first — recolors every accent/highlight icon
# across the whole upstream theme. Dedicated + engine passes below write
# on top of this, so hand-curated app icons still take priority.
time_step "patch_full_breeze_theme" patch_full_breeze_theme

# Dedicated functions next, so the engine knows what's already handled
time_step "patch_folder_icons"             patch_folder_icons
time_step "patch_trash_icon"               patch_trash_icon
time_step "patch_kdeconnect_places_icon"   patch_kdeconnect_places_icon
time_step "patch_inode_directory_icon"     patch_inode_directory_icon
time_step "patch_system_file_manager_icon" patch_system_file_manager_icon
time_step "patch_preferences_system_icon"  patch_preferences_system_icon
time_step "patch_dolphin_icon"             patch_dolphin_icon
time_step "patch_cachyos_hello_icon"       patch_cachyos_hello_icon
#patch_cachyos_kernel_manager_icon
time_step "patch_discord_vesktop_icons"    patch_discord_vesktop_icons
#patch_nativmix_icon
#time_step "patch_orcaslicer_icon"          patch_orcaslicer_icon
#patch_conky_icon

# The generic engine — everything else, games included
time_step "patch_all_desktop_icons" patch_all_desktop_icons

# Non-.desktop icon sets
time_step "patch_wlogout_icons" patch_wlogout_icons
time_step "patch_osd_icons"     patch_osd_icons

# Tray icons — split into its own file, see trayIconPatcher.sh
time_step "trayIconPatcher.sh" "$SUPPORT/trayIconPatcher.sh" "$color"

_run_update_desktop_database() {
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
}
time_step "update-desktop-database" _run_update_desktop_database

time_step "cleanup_icon_cache" cleanup_icon_cache

echo "Icons patched with $accent"