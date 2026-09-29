#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# Full breeze-dark theme pass — recolors every upstream SVG referencing
# ColorScheme-Accent/Highlight (folders, places, status icons, category
# icons, ...), plus ColorScheme-Text specifically in status/devices/actions
# (breeze's monochrome "symbolic" tray glyphs, which otherwise stay
# unthemed). ColorScheme-Text elsewhere and semantic status colors
# (success/error/warning) are left alone — they either resolve for free via
# Inherits=breeze-dark or carry meaning that shouldn't be overridden.
# Runs BEFORE the dedicated per-app functions and generic engine, so
# hand-curated app icons always win over anything this pass writes.
# ---------------------------------------------------------------------------
# Bootstraps index.theme from scratch on a fresh machine, where
# breeze-dark-accent may not exist as a theme yet. Without its
# Inherits=breeze-dark line, anything this pipeline hasn't explicitly
# recolored has no fallback at all — a fresh install would show "no icon"
# for almost everything, not just the handful of apps actually themed here.
ensure_icon_theme_index() {
    local themeFile="$iconThemeDir/index.theme"
    [ -f "$themeFile" ] && return 0

    mkdir -p "$iconThemeDir"
    cat > "$themeFile" << 'EOF'
[Icon Theme]
Name=Breeze Dark Accent
Comment=Breeze Dark with dynamic accent color theming
Inherits=breeze-dark
Directories=
EOF
    echo "  breeze-dark-accent/index.theme created (was missing — fresh install bootstrap)"
}

# Registers the directories this pipeline's own custom/override icons get
# written into — apps/scalable above all, since ensure_icon() puts nearly
# every generated app icon there. update_index_theme_directories (below)
# only copies stanzas FROM breeze-dark's own index.theme for directories
# the breeze-mirror pass wrote to, so it never touches apps/scalable —
# without this, those files would sit on disk correctly colored but
# invisible to icon lookup (a directory not listed in Directories= doesn't
# exist as far as GTK/Qt are concerned). Stanzas are hand-written here
# rather than copied, since breeze-dark doesn't define matching sections
# for some of these (e.g. size 44 is nonstandard).
ensure_app_icon_directories() {
    local themeFile="$iconThemeDir/index.theme"
    [ -f "$themeFile" ] || return 1

    python3 - "$themeFile" << 'PYEOF'
import configparser, sys

themeFile = sys.argv[1]

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
cp.read(themeFile)

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

with open(themeFile, "w") as f:
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
    # the final writtenDirs set needs merging afterward), so this is a
    # clean fit for parallelizing across cores rather than walking the
    # whole tree in a single process. Collecting the file list itself
    # stays single-threaded since that part is cheap (just os.walk, no
    # file I/O yet) — only the actual per-file work is farmed out.
    local dirsFile
    dirsFile=$(mktemp)

    python3 - "$SRC" "$iconThemeDir" "$accent" "$dirsFile" "$symbolicAccent" << 'PYEOF'
import multiprocessing as mp
import os, re, sys

src_root, dst_root, accent, dirsFile, symbolicAccent = sys.argv[1:6]

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
writtenDirs = set()

worker_count = max(1, (os.cpu_count() or 4) // 2)
# Explicitly force "fork" rather than relying on Python's current default
# start method. forkserver/spawn need to re-import the main script from a
# real file path to set up worker processes — impossible here since this
# whole thing runs via `python3 - <<PYEOF` fed through stdin, with no file
# on disk to re-import. fork just duplicates the already-running process
# in memory instead, so it works regardless of what Python's default is
# on a given system/version.
ctx = mp.get_context("fork")
with ctx.Pool(processes=worker_count, initializer=_init_worker, initargs=(accent, symbolicAccent)) as pool:
    for result in pool.imap_unordered(_process_one, tasks, chunksize=32):
        if result is not None:
            writtenDirs.add(result)
            count += 1

with open(dirsFile, "w") as fh:
    fh.write("\n".join(sorted(writtenDirs)))

print(f"Full breeze-dark pass: {count} icons recolored across {worker_count} workers (accent={accent}, symbolic={symbolicAccent})")
PYEOF

    if [ -s "$dirsFile" ]; then
        local writtenDirs=()
        mapfile -t writtenDirs < "$dirsFile"
        update_index_theme_directories "${writtenDirs[@]}"
    fi
    rm -f "$dirsFile"
}

# update_index_theme_directories <dir1> [dir2] ...
# Ensures each given directory (relative, e.g. "status/22") has a section
# in breeze-dark-accent/index.theme, copying its Size/Type/Context stanza
# from breeze-dark's own index.theme (source of truth for correctness),
# and keeps the top-level Directories= list in sync. Idempotent — safe to
# call on every run, only ever adds sections, never removes.
update_index_theme_directories() {
    local themeFile="$iconThemeDir/index.theme"
    local srcTheme="/usr/share/icons/breeze-dark/index.theme"
    [ -f "$themeFile" ] || { echo "  $themeFile missing, skipping index.theme sync"; return 1; }
    [ -f "$srcTheme" ]  || { echo "  breeze-dark/index.theme not found, skipping sync"; return 1; }

    python3 - "$themeFile" "$srcTheme" "$@" << 'PYEOF'
import configparser, sys

themeFile, srcTheme, *new_dirs = sys.argv[1:]

def load(path):
    cp = configparser.ConfigParser(strict=False)
    cp.optionxform = str  # preserve case
    cp.read(path)
    return cp

local = load(themeFile)
src = load(srcTheme)

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
with open(themeFile, "w") as f:
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
# files in handledDesktops via patch_desktop_icon.
# ===========================================================================

patch_folder_icons() {
    for size in 16 22 24 32 48 64 96; do
        src="/usr/share/icons/breeze-dark/places/$size/folder.svg"
        dst="$iconThemeDir/places/$size/folder.svg"
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
            dst="$iconThemeDir/places/$size/$name.svg"
            mkdir -p "$(dirname "$dst")"
            sed "s/ColorScheme-Text { color: #[0-9a-fA-F]*/ColorScheme-Text { color: $symbolicAccent/g" "$src" > "$dst"
        done
    done
    echo "Trash icon replaced with symbolic version (symbolic=$symbolicAccent)"
}

# Dolphin's Places-panel entry for a KDE Connect device is a manually
# created bookmark (kdeconnectd writes it into user-places.xbel), not a
# .desktop-driven app icon — and its bookmark:icon name is "kdeconnect"
# (no underscore), a different name than the "kde_connect" the engine
# already generates via icon-overrides.conf for the app's own .desktop entries.
# Exact-match icon lookup means that one-character difference is enough to
# miss entirely. Same artwork, just also written under the name Dolphin
# actually asks for here. Uses symbolicAccent (matugen's primary) rather than the
# raw seed accent, since this sits in the Places panel alongside other
# device/status entries rather than functioning as a standalone app icon.
patch_kdeconnect_places_icon() {
    local src="$iconsDir/kde_connect_base_icon.svg"
    if [ ! -f "$src" ]; then
        echo "  kde_connect_base_icon.svg not found, skipping KDE Connect places icon"
        return 1
    fi
    local dst="$iconThemeDir/apps/scalable/kdeconnect.svg"
    sed "s/currentColor/$symbolicAccent/g" "$src" > "$dst"
    echo "KDE Connect places-panel icon patched (symbolic=$symbolicAccent)"
}

patch_inode_directory_icon() {
    src="/usr/share/icons/breeze-dark/mimetypes/64/inode-directory.svg"
    dst="$iconThemeDir/mimetypes/64/inode-directory.svg"
    [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
}

patch_system_file_manager_icon() {
    for size in 16 22 24 32 48 64; do
        src="/usr/share/icons/breeze-dark/apps/$size/system-file-manager.svg"
        dst="$iconThemeDir/apps/$size/system-file-manager.svg"
        [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
    done
}

patch_preferences_system_icon() {
    for size in 16 32 48; do
        src="/usr/share/icons/breeze-dark/apps/$size/preferences-system.svg"
        dst="$iconThemeDir/apps/$size/preferences-system.svg"
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
with open("$iconThemeDir/apps/scalable/org.kde.dolphin.svg", "w") as f:
    f.write(content)
print("Dolphin icon patched")
EOF
        patch_desktop_icon "org.kde.dolphin" "org.kde.dolphin.desktop"
    fi
}