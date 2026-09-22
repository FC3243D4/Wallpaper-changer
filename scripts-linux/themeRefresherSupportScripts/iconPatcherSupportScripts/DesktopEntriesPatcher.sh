#!/usr/bin/env bash

# Manual slug -> icon overrides. Kept in its own file (not this script) so
# adding/removing an override never means editing bash. Format and
# instructions are documented in the file itself. Read directly by the
# Python engine in patch_all_desktop_icons — never loaded into a bash
# associative array, so there's no per-run parse/convert step for it at all.
iconOverridesConf="$supportDir/icon-overrides.conf"

desktopDirs=(
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
desktopOverrideMarker="X-IconPatcherManaged=true"

# Retroactively tags user-dir .desktop files created by earlier runs,
# before the override-marker system existed. Only tags a file if a system
# .desktop with the same basename still exists (i.e. it's demonstrably
# still shadowing something real, so it's safe to prune later once that
# original disappears). A basename with no system counterpart is left
# alone — could be a genuine user-only entry (Steam/Heroic shortcut) or
# an already-orphaned override; either way it needs a manual check.
backfill_desktop_override_markers() {
    local userDir="$HOME/.local/share/applications"
    [ -d "$userDir" ] || return 0
    local systemDirs=(
        "/usr/share/applications"
        "/usr/local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
        "$HOME/.local/share/flatpak/exports/share/applications"
    )
    local marked=0
    while IFS= read -r -d '' f; do
        grep -qxF "$desktopOverrideMarker" "$f" 2>/dev/null && continue
        local base found=0
        base=$(basename "$f")
        for dir in "${systemDirs[@]}"; do
            [ -f "$dir/$base" ] && { found=1; break; }
        done
        if [ "$found" -eq 1 ]; then
            if [ -w "$f" ]; then
                echo "$desktopOverrideMarker" >> "$f"
                marked=$((marked + 1))
            else
                echo "  skipping $base (not writable — likely created by something else with elevated privileges)"
            fi
        fi
    done < <(find "$userDir" -maxdepth 1 -type f -name "*.desktop" -print0 2>/dev/null)
    [ "$marked" -gt 0 ] && echo "Backfilled override marker on $marked existing .desktop file(s)"
}

# Removes marked overrides once the system .desktop file they shadow no
# longer exists (app uninstalled) — otherwise a stale user-dir copy
# shadows the nonexistent original forever, and uninstalled apps keep
# appearing in launchers. Only ever touches marked files. Runs before
# anything else scans desktopDirs.
cleanup_stale_desktop_overrides() {
    local userDir="$HOME/.local/share/applications"
    [ -d "$userDir" ] || return 0
    backfill_desktop_override_markers
    local systemDirs=(
        "/usr/share/applications"
        "/usr/local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
        "$HOME/.local/share/flatpak/exports/share/applications"
    )

    # Each file's check (marker grep + up to 4 systemDirs stats + possible
    # removal) is fully independent of every other file — genuinely
    # embarrassingly parallel, one per candidate .desktop file. A
    # background subshell can't set `removed` in this shell directly, so
    # each one signals "I removed a file" via exit code 1 (vs 0 for
    # "nothing to remove") the same way ferdiumIconPatcher.sh's
    # restarted_needed does; the loop below turns that back into a count.
    check_one_override() {
        local f="$1"
        grep -qxF "$desktopOverrideMarker" "$f" 2>/dev/null || return 0
        local base found=0
        base=$(basename "$f")
        for dir in "${systemDirs[@]}"; do
            [ -f "$dir/$base" ] && { found=1; break; }
        done
        if [ "$found" -eq 0 ]; then
            rm -f "$f"
            echo "  removed stale override: $base (no longer installed)"
            return 1
        fi
        return 0
    }

    local removed=0
    local maxParallel=16
    declare -a checkPids=()
    while IFS= read -r -d '' f; do
        check_one_override "$f" &
        checkPids+=("$!")
        if [ "${#checkPids[@]}" -ge "$maxParallel" ]; then
            wait "${checkPids[0]}"
            [ "$?" -eq 1 ] && removed=$((removed + 1))
            checkPids=("${checkPids[@]:1}")
        fi
    done < <(find "$userDir" -maxdepth 1 -type f -name "*.desktop" -print0 2>/dev/null)
    for pid in "${checkPids[@]}"; do
        wait "$pid"
        [ "$?" -eq 1 ] && removed=$((removed + 1))
    done

    if [ "$removed" -gt 0 ]; then
        echo "Cleaned up $removed stale .desktop override(s)"
        update-desktop-database "$userDir" 2>/dev/null
    fi
}

# .desktop basenames already themed by a dedicated function this run —
# the generic engine skips these. Filled in by patch_desktop_icon.
declare -A handledDesktops
# Icon names already generated this run (many apps share one generic icon,
# no point recoloring it more than once).
declare -A generatedIcons

# ---------------------------------------------------------------------------
# Manual slug -> icon overrides (the games-style map, now for everything)
# live in $iconOverridesConf, not here — see that file for the format, how
# to find a slug, and the full current list. It's read directly by the
# Python engine in patch_all_desktop_icons.
# ---------------------------------------------------------------------------
# Color-token overrides — how to recolor each base icon.
# Key   = icon base name (the resolved value above, or the raw slug).
# Value = space-separated list of tokens to replace with the accent,
#         or "@inject" to add fill="$accent" on the root <svg> tag
#         (for icons with no explicit fill at all).
# Anything not listed here defaults to replacing "currentColor".
# ---------------------------------------------------------------------------
declare -A colorTokens=(

)

# ---------------------------------------------------------------------------
# Category fallbacks — checked in order, first match wins, so keep the
# specific desktop categories before the broad ones. Values are icon base
# names ($iconsDir/<name>_base_icon.svg must exist for the fallback to apply).
# ---------------------------------------------------------------------------
categoryFallbacks=(
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
# Only used if $iconsDir/application_base_icon.svg actually exists — otherwise
# unmatched entries are left untouched.
catchallIcon="application"

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

# patch_desktop_file <iconName> <exact_path> and patch_desktop_icon
# <iconName> <glob_pattern> [more...] both create/update a user-level
# Icon= override in ~/.local/share/applications when it doesn't already
# match iconName (XDG standard: user overrides win, no root needed,
# survive package updates). patch_desktop_icon glob-matches files across
# the known application dirs; patch_desktop_file takes one exact path, so
# it also handles basenames with spaces (Steam/Heroic shortcuts) safely —
# that's the one the generic engine calls directly. Every matched
# basename is registered in handledDesktops so the engine won't reprocess it.
patch_desktop_file() {
    local iconName="$1" file="$2"
    [ -f "$file" ] || return 1
    local base
    base="$(basename "$file")"
    handledDesktops[$base]=1
    local userDir="$HOME/.local/share/applications"
    local override
    # A file already inside the user dir — including subdirs such as
    # wine/Programs/... — is edited IN PLACE. Copying it to the top level
    # would create a second entry: the XDG desktop-file ID of
    # wine/Programs/Foo/Foo.desktop is "wine-Programs-Foo-Foo.desktop", so a
    # top-level Foo.desktop does NOT shadow it and the app shows up twice.
    # Only files from system/flatpak dirs get a user-level override copy.
    case "$file" in
        "$userDir"/*) override="$file" ;;
        *)            override="$userDir/$base" ;;
    esac
    local current
    # If a user override already exists, that's what the desktop
    # actually reads — compare against it, not the system file,
    # or every run re-reports (and rewrites) the same change.
    if [ -f "$override" ]; then
        current=$(grep -m1 "^Icon=" "$override" | cut -d= -f2-)
    else
        current=$(grep -m1 "^Icon=" "$file" | cut -d= -f2-)
    fi
    if [ "$current" != "$iconName" ]; then
        mkdir -p "$HOME/.local/share/applications"
        # Some installers (e.g. Autodesk-Unofficial) create their .desktop
        # files mode 444. If WE own the file, temporarily add u+w and
        # restore the original mode afterwards; files owned by someone else
        # are still skipped.
        local restoreMode=""
        if [ -f "$override" ] && [ ! -w "$override" ]; then
            if [ -O "$override" ]; then
                restoreMode=$(stat -c %a "$override")
                chmod u+w "$override"
            else
                echo "  skipping $base (existing override not writable — likely created by something else with elevated privileges)"
                return 1
            fi
        fi
        if [ ! -f "$override" ]; then
            cp "$file" "$override"
            # Marks this as OUR copy of a system file, not a genuine
            # user-only .desktop entry (e.g. Steam/Heroic game shortcuts,
            # which live solely in this directory and must never be
            # pruned). Only files bearing this marker are ever considered
            # for removal by cleanup_stale_desktop_overrides.
            echo "$desktopOverrideMarker" >> "$override"
        fi
        if grep -q "^Icon=" "$override"; then
            if [ "$override" = "$file" ] \
               && ! grep -qxF "$desktopOverrideMarker" "$override" \
               && ! grep -q "^#Icon=" "$override"; then
                # Edited in place and NOT one of our copies (e.g. a Wine
                # entry under applications/wine/): the Icon= line is the
                # only record of the original icon, so keep it as a comment
                # and add the patched one after it. Done once per file —
                # later runs (and icon changes) only rewrite the active
                # Icon= line, so the commented original is never clobbered.
                # If Wine regenerates the file, the fresh Icon= is
                # commented again on the next run.
                sed -i "s|^Icon=\(.*\)|#Icon=\1\nIcon=$iconName|" "$override"
            else
                sed -i "s|^Icon=.*|Icon=$iconName|" "$override"
            fi
        else
            echo "Icon=$iconName" >> "$override"
        fi
        [ -n "$restoreMode" ] && chmod "$restoreMode" "$override"
        echo "  .desktop updated: $base (Icon: ${current:-<none>} -> $iconName)"
    fi
}

patch_desktop_icon() {
    local iconName="$1"; shift
    local patterns=("$@")
    local matched=0
    shopt -s nullglob nocaseglob
    for dir in "${desktopDirs[@]}"; do
        [ -d "$dir" ] || continue
        for pattern in "${patterns[@]}"; do
            for file in "$dir"/$pattern; do
                [ -f "$file" ] || continue
                matched=1
                patch_desktop_file "$iconName" "$file"
            done
        done
    done
    shopt -u nullglob nocaseglob
    [ "$matched" -eq 0 ] && echo "  no .desktop file found for $iconName"
}

# ---------------------------------------------------------------------------
# The generic engine — formerly ~50 per-app functions + gamesIconPatcher.sh
# ---------------------------------------------------------------------------
patch_all_desktop_icons() {
    # The scan/decide phase (slugify, category fallback, game detection,
    # cross-dir dedup) runs as one Python pass instead of per-file
    # grep/cut/tr/sed forks — for a few hundred .desktop files that's the
    # difference between 1500+ subprocess spawns and none. Only files the
    # pass decides need something written get the actual bash-side writes
    # (ensure_icon/patch_desktop_file) below.
    local categoryFallbacksFile handledFile matchesFile
    categoryFallbacksFile=$(mktemp)
    handledFile=$(mktemp)
    matchesFile=$(mktemp)

    local k
    local entry
    for entry in "${categoryFallbacks[@]}"; do
        printf '%s\n' "$entry"
    done > "$categoryFallbacksFile"

    for k in "${!handledDesktops[@]}"; do
        printf '%s\n' "$k"
    done > "$handledFile"

    [ "$dryRun" -eq 0 ] && echo "Scanning .desktop files..."

    python3 - "$iconOverridesConf" "$categoryFallbacksFile" "$handledFile" \
              "$gameIconsDir" "$iconsDir" "$catchallIcon" "$dryRun" "$matchesFile" \
              "${desktopDirs[@]}" << 'PYEOF'
import os, re, sys

iconOverridesConf, categoryFallbacksFile, handledFile, game_icons_dir, icons_dir, catchall_icon, dry_run, matchesFile = sys.argv[1:9]
desktop_dirs = sys.argv[9:]
dry_run = dry_run == "1"

# Read straight from the user-editable conf file — no bash-side conversion
# step. Format: "slug = icon_base_name" per line, "#" comments, blank lines
# ignored (see icon-overrides.conf for the full documentation). One pass,
# no regex needed for the common case.
icon_overrides = {}
if os.path.isfile(iconOverridesConf):
    with open(iconOverridesConf) as f:
        for line in f:
            line = line.strip()
            if not line or line[0] == "#":
                continue
            k, sep, v = line.partition("=")
            if not sep:
                continue
            icon_overrides[k.strip()] = v.strip()
else:
    print(f"  warning: {iconOverridesConf} not found, no overrides loaded", file=sys.stderr)

category_fallbacks = []
with open(categoryFallbacksFile) as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        cat, icon = line.split(":", 1)
        category_fallbacks.append((cat, icon))

handled = set()
with open(handledFile) as f:
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
            desktopFile = os.path.join(root, fname)
            base = fname

            if base in seen:
                continue
            seen.add(base)

            if base in handled:
                if dry_run:
                    dry_lines.append((f"({base})", "-", "-", "dedicated function"))
                continue

            try:
                with open(desktopFile, "r", errors="ignore") as fh:
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
                matches.append((desktopFile, icon, name, reason))

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
    with open(matchesFile, "w") as f:
        for desktopFile, icon, name, reason in matches:
            f.write(f"{desktopFile}\t{icon}\t{name}\t{reason}\n")
    print(
        f"Engine summary: {custom} custom/override, {games_fallback} game fallback, "
        f"{by_category} by category, {catchall} catch-all, {untouched} untouched."
    )
PYEOF

    if [ "$dryRun" -eq 1 ]; then
        rm -f "$categoryFallbacksFile" "$handledFile" "$matchesFile"
        return 0
    fi

    # Two phases, deliberately kept apart:
    #  1. Generate every icon this run actually needs, ONCE each, serially.
    #     ensure_icon's generatedIcons memoization is what stops the same
    #     base SVG being recolored once per match sharing it (e.g. every
    #     one of the "gaming" fallback entries) — a background subshell
    #     only ever sees its own fork-time copy of that cache, so
    #     parallelizing this phase would silently multiply duplicate work
    #     and, worse, have several subshells write the same output SVG
    #     path at once.
    #  2. Patch each matched .desktop file — safe to parallelize now:
    #     every one writes to its OWN uniquely-named override file
    #     (python's earlier `seen` dedup by basename guarantees no two
    #     matches share a target), and every icon phase 1 might need
    #     already exists on disk before this starts — patch_desktop_file
    #     never calls ensure_icon itself. Capped at maxParallel concurrent
    #     jobs rather than firing all of them at once, since a few hundred
    #     matches would otherwise mean a few hundred simultaneous
    #     grep/sed/cp spawns.
    local desktopFile icon name reason
    declare -A iconsNeeded=()
    while IFS=$'\t' read -r desktopFile icon name reason; do
        [ -z "$desktopFile" ] && continue
        iconsNeeded[$icon]=1
    done < "$matchesFile"
    for icon in "${!iconsNeeded[@]}"; do
        ensure_icon "$icon" || echo "  base SVG for '$icon' vanished mid-run — files needing it will be skipped"
    done

    local maxParallel=16
    declare -a patchPids=()
    while IFS=$'\t' read -r desktopFile icon name reason; do
        [ -z "$desktopFile" ] && continue
        if [ -z "${generatedIcons[$icon]:-}" ]; then
            echo "  '$name' -> base SVG for '$icon' vanished mid-run, skipping"
            continue
        fi
        (
            outfile=$(mktemp)
            {
                echo "'$name' -> $icon ($reason)"
                patch_desktop_file "$icon" "$desktopFile"
            } > "$outfile" 2>&1
            cat "$outfile"
            rm -f "$outfile"
        ) &
        patchPids+=("$!")
        if [ "${#patchPids[@]}" -ge "$maxParallel" ]; then
            wait "${patchPids[0]}"
            patchPids=("${patchPids[@]:1}")
        fi
    done < "$matchesFile"
    for pid in "${patchPids[@]}"; do
        wait "$pid"
    done

    rm -f "$categoryFallbacksFile" "$handledFile" "$matchesFile"
}

# category_fallback_icon <desktopFile> — echoes the icon name for the first
# matching Categories= entry (only if its base SVG exists). Returns 1 if no
# category matches.
category_fallback_icon() {
    local f="$1" categories entry cat icon
    categories=$(grep -m1 '^Categories=' "$f" | cut -d= -f2-)
    [ -n "$categories" ] || return 1
    for entry in "${categoryFallbacks[@]}"; do
        cat="${entry%%:*}"
        icon="${entry#*:}"
        if [[ ";$categories;" == *";$cat;"* ]] && [ -f "$iconsDir/${icon}_base_icon.svg" ]; then
            echo "$icon"
            return 0
        fi
    done
    return 1
}