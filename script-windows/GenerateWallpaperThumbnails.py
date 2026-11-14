#!/usr/bin/env python3
"""Pre-generate the wallpaper picker's thumbnails (Windows counterpart of
GenerateWallpaperThumbnails.sh).

Uses the picker's own thumbnail code (WallpaperGui.load_or_make_thumbnail) and cache
layout, so what this writes is exactly what the picker would have generated lazily -
it just does it ahead of time, in parallel, and skips thumbnails that are already
up to date.

Usage: GenerateWallpaperThumbnails.py [--wallpapers DIR] [--ratios 16-9,21-9] [--jobs N] [--quiet]
Without --ratios every aspect-ratio folder (named like 16-9) under the wallpaper folder is done.
"""
import argparse
import importlib.util
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")      # no window, no display needed


_APP = None   # keeps the Qt application object alive for the whole run


def load_picker():
    """Import WallpaperGui.py from this folder (installed side by side) or the repo's scripts-linux."""
    here = os.path.dirname(os.path.abspath(__file__))
    for cand in (os.path.join(here, "WallpaperGui.py"), os.path.join(here, "..", "scripts-linux", "WallpaperGui.py")):
        if os.path.isfile(cand):
            spec = importlib.util.spec_from_file_location("WallpaperGui", cand)
            mod = importlib.util.module_from_spec(spec)
            sys.modules["WallpaperGui"] = mod
            spec.loader.exec_module(mod)
            return mod
    sys.exit("WallpaperGui.py not found next to this script.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wallpapers", help="wallpaper library (default: the picker's configured folder)")
    ap.add_argument("--ratios", help="comma-separated aspect folders, e.g. 16-9,21-9 (default: all)")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    gui = load_picker()
    from PyQt6.QtGui import QGuiApplication
    global _APP
    _APP = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])   # image plugins need an application object

    base = args.wallpapers or gui.default_wallpaper_dir()
    cache_dir, _ = gui.default_cache_paths()
    if not os.path.isdir(base):
        sys.exit(f"Wallpaper folder not found: {base}")
    wanted = [r.strip() for r in args.ratios.split(",") if r.strip()] if args.ratios else None
    folders = sorted(d for d in os.listdir(base)
                     if re.match(r"^\d+-\d+$", d) and os.path.isdir(os.path.join(base, d))
                     and (wanted is None or d in wanted))
    if not folders:
        sys.exit(f"No aspect-ratio folders to process in {base}")

    jobs = []   # (source file, thumbnail path)
    for folder in folders:
        wall_dir = os.path.join(base, folder)
        for root, _dirs, files in os.walk(wall_dir, followlinks=True):
            for name in files:
                if name.lower().endswith(gui.IMAGE_EXTS):
                    src = os.path.join(root, name)
                    jobs.append((src, gui.thumbnail_cache_path(cache_dir, wall_dir, src)))
    total = len(jobs)
    if not args.quiet:
        print(f"Found {total} wallpapers in {', '.join(folders)}. Generating thumbnails with {args.jobs} threads...", flush=True)
    if total == 0:
        return 0

    def work(job):
        src, thumb = job
        try:
            if os.path.getmtime(thumb) >= os.path.getmtime(src):
                return "SKIP"
        except OSError:
            pass
        img = gui.load_or_make_thumbnail(src, thumb)
        return "FAIL" if img.isNull() or not os.path.exists(thumb) else "OK"

    counts = {"OK": 0, "SKIP": 0, "FAIL": 0}
    last = 0.0
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for i, result in enumerate(pool.map(work, jobs), 1):
            counts[result] += 1
            now = time.monotonic()
            if not args.quiet and (now - last > 0.5 or i == total):
                print(f"\r[{i}/{total}] {i * 100 // total:3d}%", end="", flush=True)
                last = now
    if not args.quiet:
        print(f"\nDone: {counts['OK']} generated, {counts['SKIP']} skipped, {counts['FAIL']} failed")
        print(f"Thumbnails stored in: {cache_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
