#!/usr/bin/env python3
"""Wallpaper selector GUI.

Usage: WallpaperGui.py [ASPECT_FOLDER]     e.g. WallpaperGui.py 21-9

Without an argument the folder to browse is chosen with
~/.config/WallpaperChanger/AspectRatioChecker.sh from the resolution of the
monitor the window opens on (focused Hyprland monitor, else the screen under
the cursor).
"""
import html
import json
import os
import random
import re
import sys
import sqlite3
import subprocess
import threading
from collections import OrderedDict
from contextlib import closing
from functools import lru_cache
from itertools import groupby

from PyQt6.QtCore import (
    Qt, QSize, QLoggingCategory, QTimer, QThread, QThreadPool, QRunnable,
    QObject, QAbstractListModel, QModelIndex, QSettings, pyqtSignal, pyqtSlot
)
from PyQt6.QtGui import (
    QPixmap, QIcon, QImage, QImageReader, QKeySequence, QShortcut,
    QPixmapCache, QGuiApplication, QCursor, QPalette
)
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QHBoxLayout, QVBoxLayout,
    QTreeWidget, QTreeWidgetItem, QLabel, QListView, QAbstractItemView,
    QPushButton, QCheckBox, QSplitter, QMessageBox, QWidget, QLineEdit,
    QSizePolicy, QSlider
)

# Suppress harmless Wayland text-input warnings
QLoggingCategory.setFilterRules("qt.qpa.wayland.textinput.warning=false")

THUMB_MAX = 600                       # longest side of a cached thumbnail
PREVIEW_MAX = 2560                    # longest side the preview is decoded at
QUICKLOOK_MAX = 3840                  # longest side Quick Look is decoded at
THUMB_MEMORY_BUDGET = 192 * 1024**2   # decoded thumbnails kept in RAM (bytes)
IMAGE_EXTS = ('png', 'jpg', 'jpeg')

THUMB_WIDTH_MIN = 240                 # thumbnails are for judging a wallpaper:
THUMB_WIDTH_MAX = 520                 # never allow them to get tiny
THUMB_WIDTH_DEFAULT = 280
BLUR_DIVISOR = 20                     # NSFW blur strength (bigger = blurrier)

ASPECT_SCRIPT = os.path.expanduser("~/.config/WallpaperChanger/AspectRatioChecker.sh")

# --- Default window size ---------------------------------------------------
# Fraction of the monitor's width / height the window opens with, keyed by the
# aspect-ratio folder in use (the one AspectRatioChecker.sh picked for the monitor).
# Sizes are in logical pixels (monitor scale already taken into account).
WINDOW_SIZE_PERCENT = {
    #  folder    (width, height)
    "16-9":  (0.70, 0.75),
    "16-10": (0.70, 0.78),
    "21-9":  (0.55, 0.75),
    "32-9":  (0.45, 0.80),
}
WINDOW_SIZE_DEFAULT_PERCENT = (0.65, 0.75)   # folder not listed above
WINDOW_SIZE_FALLBACK_PX = (1300, 850)        # monitor size couldn't be detected
WINDOW_MIN_PX = (900, 600)                   # never smaller than this (unless the screen is)
REMEMBER_WINDOW_SIZE = False                 # True: last size per folder beats the percentages

KEY_ROLE = Qt.ItemDataRole.UserRole           # tree: ("all",) / ("series", s) / ("char", s, c)
NAME_ROLE = Qt.ItemDataRole.UserRole + 1      # tree: display name without count
COUNT_ROLE = Qt.ItemDataRole.UserRole + 2     # tree: [sfw_count, nsfw_count]


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
@lru_cache(maxsize=None)
def natural_sort_key(s):
    # Memoised: the same ~11k paths get re-sorted on every filter change.
    return tuple(int(text) if text.isdigit() else text.lower() for text in re.split(r'(\d+)', s))


def format_character_name(name):
    if '-' in name:
        parts = name.split('-')
        formatted_parts = [format_single_camel(p) for p in parts if p]
        return " & ".join(formatted_parts)
    else:
        return format_single_camel(name)


def format_single_camel(s):
    if not s:
        return s
    spaced = re.sub(r'([a-z0-9])([A-Z])', r'\1 \2', s)
    return spaced.lower()


def parse_wallpaper_name(filename):
    """'nsfw-rem-ram-3.png' -> (True, ['rem', 'ram'])."""
    name = os.path.splitext(filename)[0]
    is_nsfw = name.lower().startswith("nsfw-")
    clean = name[5:] if is_nsfw else name
    parts = [c.strip() for c in clean.split('-') if c.strip()]
    characters = [c for c in parts if not c.isdigit()]
    return is_nsfw, (characters or ["General"])


def is_nsfw_path(path):
    return os.path.basename(path).lower().startswith("nsfw-")


def ensure_schema(conn):
    conn.execute("""
        CREATE TABLE IF NOT EXISTS wallpapers (
            path TEXT PRIMARY KEY,
            series TEXT,
            characters TEXT,
            is_nsfw INTEGER,
            is_group INTEGER,
            mtime REAL
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_series ON wallpapers(series)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_nsfw ON wallpapers(is_nsfw)")
    conn.commit()


def read_scaled(path, max_dim):
    """Decode an image no larger than max_dim on its longest side.

    Uses QImageReader.setScaledSize so the decoder can downscale while reading
    instead of decoding the full 4K bitmap and scaling afterwards. Works on QImage,
    so it is safe to call off the GUI thread.
    """
    reader = QImageReader(path)
    size = reader.size()
    if size.isValid() and (size.width() > max_dim or size.height() > max_dim):
        size.scale(max_dim, max_dim, Qt.AspectRatioMode.KeepAspectRatio)
        reader.setScaledSize(size)
    return reader.read()


def _same_aspect(a, b, tolerance=0.03):
    if not a.isValid() or not b.isValid() or a.height() == 0 or b.height() == 0:
        return True     # can't tell: trust the thumbnail
    ra, rb = a.width() / a.height(), b.width() / b.height()
    return abs(ra - rb) / rb <= tolerance


def load_or_make_thumbnail(src, thumb_path):
    """Return the thumbnail as a QImage, generating + caching it if needed."""
    src_size = QImageReader(src).size()
    try:
        if os.path.getmtime(thumb_path) >= os.path.getmtime(src):
            img = QImage(thumb_path)
            # The cache is keyed by path relative to the aspect folder, so two
            # folders (16-9 / 21-9) share names: reject a thumbnail whose shape
            # doesn't match this source and regenerate it.
            if not img.isNull() and _same_aspect(img.size(), src_size):
                return img
    except OSError:
        pass  # missing or unreadable -> regenerate

    img = read_scaled(src, THUMB_MAX)
    if img.isNull():
        return img

    try:
        os.makedirs(os.path.dirname(thumb_path), exist_ok=True)
        tmp = f"{thumb_path}.{os.getpid()}.{threading.get_ident()}.tmp"
        if img.save(tmp, "JPG", 85):
            os.replace(tmp, thumb_path)   # atomic: never leaves half-written thumbs
    except OSError:
        pass
    return img


def make_blurred(pixmap, size):
    """Soft blur that keeps the picture's colours and general shapes.

    Image pyramid: shrink in halves (each smooth pass averages 2x2 pixels) down to a
    few dozen pixels, then grow back in doubles. Cheap, and gives smooth gradients
    instead of the big blocks a single huge up-scale produces.
    """
    img = pixmap.toImage()
    small_w = max(8, img.width() // BLUR_DIVISOR)
    small_h = max(2, round(img.height() * small_w / img.width()))
    ignore, smooth = Qt.AspectRatioMode.IgnoreAspectRatio, Qt.TransformationMode.SmoothTransformation

    cur = img
    while cur.width() > small_w * 2:
        cur = cur.scaled(max(1, cur.width() // 2), max(1, cur.height() // 2), ignore, smooth)
    cur = cur.scaled(small_w, small_h, ignore, smooth)

    target = size if (size.isValid() and not size.isEmpty()) else img.size()
    while cur.width() * 2 < target.width():
        cur = cur.scaled(cur.width() * 2, cur.height() * 2, ignore, smooth)
    return QPixmap.fromImage(cur.scaled(target, Qt.AspectRatioMode.KeepAspectRatio, smooth))


def make_blur_icon(pixmap):
    # Blurred rows are *disabled* items (that's what makes them unselectable), and Qt
    # greys out the icon of a disabled item. Supplying the Disabled-mode pixmap
    # ourselves keeps the real colours.
    icon = QIcon(pixmap)
    icon.addPixmap(pixmap, QIcon.Mode.Disabled)
    return icon


# --------------------------------------------------------------------------
# Choosing the aspect-ratio folder
# --------------------------------------------------------------------------
def detect_monitor():
    """(physical_width, physical_height, scale) of the monitor the window opens on, or None."""
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        try:
            out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True,
                                 text=True, timeout=2).stdout
            monitors = json.loads(out)
            mon = next((m for m in monitors if m.get("focused")), monitors[0] if monitors else None)
            if mon:
                w, h = int(mon["width"]), int(mon["height"])
                if mon.get("transform", 0) in (1, 3, 5, 7):    # rotated 90/270
                    w, h = h, w
                return w, h, float(mon.get("scale") or 1.0)
        except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
            pass

    screen = QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
    if screen:
        size, dpr = screen.size(), screen.devicePixelRatio()
        return round(size.width() * dpr), round(size.height() * dpr), dpr
    return None


def detect_screen_resolution():
    """'WIDTHxHEIGHT' (physical pixels) of that monitor, or None."""
    monitor = detect_monitor()
    return f"{monitor[0]}x{monitor[1]}" if monitor else None


def pick_wall_dir(base_dir, override=None, resolution=None):
    if not os.path.isdir(base_dir):
        return base_dir

    # 1. explicit command-line choice
    if override and os.path.isdir(os.path.join(base_dir, override)):
        return os.path.join(base_dir, override)

    # 2. the wallpaper changer's own AspectRatioChecker.sh, so the GUI and the
    #    applicator always agree on which folder matches a display
    resolution = resolution or detect_screen_resolution()
    if resolution and os.path.isfile(ASPECT_SCRIPT):
        try:
            proc = subprocess.run(["bash", ASPECT_SCRIPT, resolution], capture_output=True,
                                  text=True, timeout=5)
            lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
            if lines:
                candidate = os.path.normpath(lines[-1])
                if os.path.isdir(candidate):
                    return candidate
        except (OSError, subprocess.SubprocessError):
            pass

    # 3. old behaviour: 16-9, else the first folder
    if os.path.isdir(os.path.join(base_dir, "16-9")):
        return os.path.join(base_dir, "16-9")
    subdirs = sorted(os.path.join(base_dir, d) for d in os.listdir(base_dir)
                     if os.path.isdir(os.path.join(base_dir, d)))
    return subdirs[0] if subdirs else base_dir


# --------------------------------------------------------------------------
# Background workers
# --------------------------------------------------------------------------
class WallpaperScannerWorker(QThread):
    scan_done = pyqtSignal(bool)   # True if the index changed

    def __init__(self, wall_dir, db_path):
        super().__init__()
        self.wall_dir = wall_dir
        self.db_path = db_path
        self._abort = False

    def abort(self):
        self._abort = True

    def _iter_images(self):
        """Yield (series, filename, full_path, mtime) using os.scandir."""
        try:
            top_level = list(os.scandir(self.wall_dir))
        except OSError:
            return

        for series_entry in top_level:
            try:
                if not series_entry.is_dir():
                    continue
            except OSError:
                continue

            stack = [series_entry.path]
            while stack:
                if self._abort:
                    return
                try:
                    with os.scandir(stack.pop()) as it:
                        for entry in it:
                            try:
                                if entry.is_dir(follow_symlinks=False):
                                    stack.append(entry.path)
                                elif entry.name.lower().endswith(IMAGE_EXTS) and entry.is_file():
                                    yield (series_entry.name, entry.name, entry.path,
                                           entry.stat().st_mtime)
                            except OSError:
                                continue
                except OSError:
                    continue

    def run(self):
        if not os.path.exists(self.wall_dir):
            self.scan_done.emit(False)
            return

        # The DB can hold several aspect folders: only ever look at / delete rows
        # that live under the folder being scanned.
        prefix = os.path.join(self.wall_dir, "")

        conn = sqlite3.connect(self.db_path)
        try:
            ensure_schema(conn)
            db_records = dict(conn.execute(
                "SELECT path, mtime FROM wallpapers WHERE substr(path, 1, ?) = ?",
                (len(prefix), prefix)))

            disk_paths = set()
            batch_data = []

            for series, f, full_path, mtime in self._iter_images():
                disk_paths.add(full_path)

                if db_records.get(full_path) == mtime:
                    continue

                is_nsfw, characters = parse_wallpaper_name(f)
                batch_data.append((full_path, series, "-".join(characters),
                                   1 if is_nsfw else 0, 1 if len(characters) > 1 else 0, mtime))

            if self._abort:
                return  # partial scan: don't touch the DB (would "delete" unseen files)

            deleted_paths = set(db_records) - disk_paths

            if batch_data:
                conn.executemany("""
                    INSERT OR REPLACE INTO wallpapers (path, series, characters, is_nsfw, is_group, mtime)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, batch_data)
            if deleted_paths:
                conn.executemany("DELETE FROM wallpapers WHERE path = ?",
                                 [(p,) for p in deleted_paths])
            conn.commit()
            self.scan_done.emit(bool(batch_data or deleted_paths))
        finally:
            conn.close()


class ThumbSignals(QObject):
    ready = pyqtSignal(str, QImage)


class ThumbJob(QRunnable):
    def __init__(self, src, thumb_path, signals):
        super().__init__()
        self.src = src
        self.thumb_path = thumb_path
        self.signals = signals

    def run(self):
        img = QImage()
        try:
            img = load_or_make_thumbnail(self.src, self.thumb_path)
        except Exception:
            pass
        self.signals.ready.emit(self.src, img)


class PreviewSignals(QObject):
    ready = pyqtSignal(int, QImage, QSize)     # sequence, image, original size


class PreviewJob(QRunnable):
    def __init__(self, path, seq, max_dim, signals):
        super().__init__()
        self.path = path
        self.seq = seq
        self.max_dim = max_dim
        self.signals = signals

    def run(self):
        img, size = QImage(), QSize()
        try:
            size = QImageReader(self.path).size()
            img = read_scaled(self.path, self.max_dim)
        except Exception:
            pass
        self.signals.ready.emit(self.seq, img, size)


# --------------------------------------------------------------------------
# Model: holds only the list of paths; thumbnails are loaded lazily for the
# rows that are actually painted.
# --------------------------------------------------------------------------
class ThumbEntry:
    __slots__ = ("pixmap", "icon", "blur", "blur_size", "base_bytes", "nbytes")

    def __init__(self, pixmap):
        self.pixmap = pixmap
        self.icon = QIcon(pixmap)
        self.blur = None
        self.blur_size = None
        self.base_bytes = pixmap.width() * pixmap.height() * 4
        self.nbytes = self.base_bytes


class ThumbCache:
    """Byte-budgeted LRU of decoded thumbnails (GUI thread only)."""

    def __init__(self, max_bytes):
        self._items = OrderedDict()
        self._bytes = 0
        self._max = max_bytes

    def get(self, key):
        entry = self._items.get(key)
        if entry is not None:
            self._items.move_to_end(key)
        return entry

    def put(self, key, pixmap):
        old = self._items.pop(key, None)
        if old:
            self._bytes -= old.nbytes
        entry = ThumbEntry(pixmap)
        self._items[key] = entry
        self._bytes += entry.nbytes
        self._evict()

    def blurred_icon(self, key, size):
        entry = self.get(key)
        if entry is None:
            return None
        if entry.blur is None or entry.blur_size != size:
            pm = make_blurred(entry.pixmap, size)
            entry.blur, entry.blur_size = make_blur_icon(pm), QSize(size)
            new_bytes = entry.base_bytes + pm.width() * pm.height() * 4
            self._bytes += new_bytes - entry.nbytes
            entry.nbytes = new_bytes
            self._evict()
        return entry.blur

    def _evict(self):
        while self._bytes > self._max and len(self._items) > 1:
            _, entry = self._items.popitem(last=False)
            self._bytes -= entry.nbytes


class WallpaperModel(QAbstractListModel):
    def __init__(self, wall_dir, cache_dir, parent=None):
        super().__init__(parent)
        self.wall_dir = wall_dir
        self.cache_dir = cache_dir

        self.paths = []
        self._rows = {}
        self._cache = ThumbCache(THUMB_MEMORY_BUDGET)
        self._inflight = set()
        self._failed = set()
        self._placeholder = QIcon()
        self._icon_size = QSize()
        self._blur_nsfw = False
        self._priority = 0

        self._signals = ThumbSignals(self)
        self._signals.ready.connect(self._on_thumb_ready)

        self._pool = QThreadPool(self)
        self._pool.setMaxThreadCount(max(2, min(6, (os.cpu_count() or 4) - 1)))

    # --- public API ---
    def set_paths(self, paths):
        self.beginResetModel()
        self._pool.clear()            # drop queued, not-yet-started thumbnail jobs
        self._inflight.clear()
        self.paths = paths
        self._rows = {p: i for i, p in enumerate(paths)}
        self.endResetModel()

    def row_of(self, path):
        return self._rows.get(path)

    def set_icon_size(self, icon_size, placeholder_icon):
        self._icon_size = icon_size
        self._placeholder = placeholder_icon

    def cached_pixmap(self, path):
        entry = self._cache.get(path)
        return entry.pixmap if entry else None

    def set_blur(self, enabled):
        if enabled == self._blur_nsfw:
            return
        self._blur_nsfw = enabled
        if self.paths:
            self.dataChanged.emit(self.index(0), self.index(len(self.paths) - 1))

    @property
    def blur_enabled(self):
        return self._blur_nsfw

    def is_blocked(self, path):
        """Blurred NSFW wallpapers can't be selected, previewed or applied."""
        return self._blur_nsfw and is_nsfw_path(path)

    def next_selectable(self, row, step):
        r = row + step
        while 0 <= r < len(self.paths):
            if not self.is_blocked(self.paths[r]):
                return r
            r += step
        return None

    def shutdown(self):
        self._pool.clear()
        self._pool.waitForDone(2000)

    # --- Qt model interface ---
    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self.paths)

    def flags(self, index):
        flags = super().flags(index)
        if index.isValid() and self.is_blocked(self.paths[index.row()]):
            # not enabled + not selectable: no click, no keyboard focus, greyed out
            flags &= ~(Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
        return flags

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid():
            return None
        path = self.paths[index.row()]

        if role == Qt.ItemDataRole.DisplayRole:
            return os.path.basename(path)
        if role == Qt.ItemDataRole.UserRole:
            return path
        if role == Qt.ItemDataRole.ToolTipRole:
            if self.is_blocked(path):
                return "Hidden: NSFW blur is on (Ctrl+B to turn it off)"
            rel = os.path.relpath(path, self.wall_dir)
            _, chars = parse_wallpaper_name(os.path.basename(path))
            return (f"{format_single_camel(rel.split(os.sep)[0])} · "
                    f"{format_character_name('-'.join(chars))}\n{os.path.basename(path)}")
        if role == Qt.ItemDataRole.DecorationRole:
            entry = self._cache.get(path)
            if entry is None:
                self._request(path)
                return self._placeholder
            if self.is_blocked(path):
                return self._cache.blurred_icon(path, self._icon_size) or self._placeholder
            return entry.icon
        return None

    # --- lazy thumbnail loading ---
    def _thumb_path(self, pic):
        rel_path = os.path.relpath(pic, self.wall_dir)
        return os.path.join(self.cache_dir, rel_path + ".jpg")

    def _request(self, path):
        if path in self._inflight or path in self._failed:
            return
        self._inflight.add(path)
        # Newest request gets the highest priority: whatever is on screen *now*
        # is loaded first, not whatever was scrolled past a moment ago.
        self._priority += 1
        self._pool.start(ThumbJob(path, self._thumb_path(path), self._signals), self._priority)

    @pyqtSlot(str, QImage)
    def _on_thumb_ready(self, path, image):
        self._inflight.discard(path)
        if image.isNull():
            self._failed.add(path)
            return
        self._cache.put(path, QPixmap.fromImage(image))
        row = self._rows.get(path)
        if row is not None:
            idx = self.index(row)
            self.dataChanged.emit(idx, idx, [Qt.ItemDataRole.DecorationRole])


# --------------------------------------------------------------------------
# Small widgets
# --------------------------------------------------------------------------
class PreviewLabel(QLabel):
    resized = pyqtSignal()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.resized.emit()


class GridView(QListView):
    zoomRequested = pyqtSignal(int)     # +1 / -1
    spacePressed = pyqtSignal()

    def wheelEvent(self, event):
        if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            self.zoomRequested.emit(1 if event.angleDelta().y() > 0 else -1)
            event.accept()
            return
        super().wheelEvent(event)

    def keyPressEvent(self, event):
        if event.key() == Qt.Key.Key_Space:
            if not event.isAutoRepeat():
                self.spacePressed.emit()
            return
        super().keyPressEvent(event)


class QuickLookOverlay(QWidget):
    """Full-window preview (Space). Left/Right browse, Enter applies, Space/Esc close."""
    closed = pyqtSignal()
    navigate = pyqtSignal(int)

    def __init__(self, parent):
        super().__init__(parent)
        self.setObjectName("quickLook")
        self.setAttribute(Qt.WidgetAttribute.WA_StyledBackground, True)
        self.setStyleSheet("#quickLook { background: rgba(8, 8, 10, 247); }")
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 24, 24, 16)
        layout.setSpacing(10)

        self.image_label = PreviewLabel()
        self.image_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.image_label.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Ignored)
        self.image_label.resized.connect(self._render)
        layout.addWidget(self.image_label, 1)

        self.caption = QLabel()
        self.caption.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.caption.setStyleSheet("color: #c9c9cf;")
        layout.addWidget(self.caption)

        hint = QLabel("←/→ browse  ·  Enter apply  ·  Space/Esc close")
        hint.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hint.setStyleSheet("color: #7d7d85; font-size: 11px;")
        layout.addWidget(hint)

        self._src = None
        self.hide()

    def set_image(self, image):
        self._src = image
        self._render()

    def set_caption(self, text):
        self.caption.setText(text)

    def showEvent(self, event):
        super().showEvent(event)
        QTimer.singleShot(0, self._render)

    def _render(self):
        if self._src is None or self._src.isNull():
            return
        dpr = self.devicePixelRatioF()
        target = self.image_label.size() * dpr
        if target.isEmpty():
            return
        scaled = self._src.scaled(target, Qt.AspectRatioMode.KeepAspectRatio,
                                  Qt.TransformationMode.SmoothTransformation)
        pixmap = QPixmap.fromImage(scaled)
        pixmap.setDevicePixelRatio(dpr)
        self.image_label.setPixmap(pixmap)

    def mousePressEvent(self, event):
        self.closed.emit()

    def keyPressEvent(self, event):
        key = event.key()
        if key in (Qt.Key.Key_Space, Qt.Key.Key_Escape):
            self.closed.emit()
        elif key in (Qt.Key.Key_Left, Qt.Key.Key_Up):
            self.navigate.emit(-1)
        elif key in (Qt.Key.Key_Right, Qt.Key.Key_Down):
            self.navigate.emit(1)
        else:
            event.ignore()


def muted(label, shrink=0):
    pal = label.palette()
    pal.setColor(QPalette.ColorRole.WindowText, pal.color(QPalette.ColorRole.PlaceholderText))
    label.setPalette(pal)
    if shrink:
        font = label.font()
        if font.pointSizeF() > 0:
            font.setPointSizeF(max(7.0, font.pointSizeF() - shrink))
            label.setFont(font)


# --------------------------------------------------------------------------
# Main window
# --------------------------------------------------------------------------
class WallpaperApp(QMainWindow):
    def __init__(self, aspect_override=None):
        super().__init__()
        self.setWindowTitle("Wallpaper Selector")

        # Scaled icons are cached by Qt in QPixmapCache (default ~10 MB), which is
        # smaller than one screenful of thumbnails -> constant re-scaling on paint.
        QPixmapCache.setCacheLimit(128 * 1024)

        # Settings live outside ~/.config/WallpaperChanger so the installer can't wipe them
        self.settings = QSettings("wallpaper-selector", "WallpaperGui")
        self._load_settings()

        self.wall_base_dir = os.path.expanduser("~/Pictures/wallpapers")
        monitor = detect_monitor()      # detected once, used for the folder *and* the size
        resolution = f"{monitor[0]}x{monitor[1]}" if monitor else None
        self.wall_dir = pick_wall_dir(self.wall_base_dir, aspect_override, resolution)
        self.resize(self._initial_window_size(monitor))
        self.setWindowTitle(f"Wallpaper Selector — {os.path.basename(self.wall_dir)}")

        self.cache_dir = os.path.expanduser("~/.cache/wallpaper-thumbnails")
        self.db_path = os.path.expanduser("~/.cache/wallpaper-changer.db")
        os.makedirs(self.cache_dir, exist_ok=True)

        # Rows in the DB belong to one aspect folder; everything is scoped to it
        prefix = os.path.join(self.wall_dir, "")
        self._scope = (len(prefix), prefix)

        self.selected_wallpaper_path = None
        self._orig_size = None
        self._updating_checkboxes = False
        self._tree_updating = False
        self._populated = False
        self._applied_state = None
        self._aspect_ratio = None
        self._layout_key = None
        self._ql_has_full = False

        # Debounce timer for smooth typing
        self.search_timer = QTimer()
        self.search_timer.setSingleShot(True)
        self.search_timer.setInterval(300)
        self.search_timer.timeout.connect(self.execute_search)

        # Preview: debounce selection (arrow-key scrolling) and resizing
        self._preview_seq = 0
        self._preview_src = None
        self.preview_timer = QTimer(self)
        self.preview_timer.setSingleShot(True)
        self.preview_timer.setInterval(60)
        self.preview_timer.timeout.connect(self._start_preview_job)
        self.preview_resize_timer = QTimer(self)
        self.preview_resize_timer.setSingleShot(True)
        self.preview_resize_timer.setInterval(40)
        self.preview_resize_timer.timeout.connect(self._render_preview)

        self.preview_pool = QThreadPool(self)
        self.preview_pool.setMaxThreadCount(1)
        self.preview_signals = PreviewSignals(self)
        self.preview_signals.ready.connect(self._on_preview_decoded)

        self.ql_pool = QThreadPool(self)
        self.ql_pool.setMaxThreadCount(1)
        self.ql_signals = PreviewSignals(self)
        self.ql_signals.ready.connect(self._on_quicklook_decoded)

        # Enter applies (or, from the search box, jumps to the results)
        for key in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
            QShortcut(QKeySequence(key), self).activated.connect(self.on_enter_pressed)
        QShortcut(QKeySequence("Ctrl+F"), self).activated.connect(self.focus_search)
        QShortcut(QKeySequence("Ctrl+B"), self).activated.connect(self.blur_checkbox_toggle)
        QShortcut(QKeySequence("Ctrl+P"), self).activated.connect(self.preview_btn_toggle)
        QShortcut(QKeySequence("Ctrl+R"), self).activated.connect(self.select_random_wallpaper)

        # 1. Build UI instantly
        self.init_ui()

        # 2. Show whatever the index already knows *right now*; the scan below
        #    only refreshes it if something actually changed on disk.
        with closing(sqlite3.connect(self.db_path)) as conn:
            ensure_schema(conn)
            has_rows = conn.execute(
                "SELECT 1 FROM wallpapers WHERE substr(path, 1, ?) = ? LIMIT 1", self._scope
            ).fetchone() is not None
        if has_rows:
            self.populate_tree(restore_key=self._saved_tree_key)

        # 3. Run incremental scanner worker in background thread
        self.scanner_thread = WallpaperScannerWorker(self.wall_dir, self.db_path)
        self.scanner_thread.scan_done.connect(self.on_scanning_finished)
        self.scanner_thread.start()

    def _initial_window_size(self, monitor):
        ratio_name = os.path.basename(self.wall_dir)

        if REMEMBER_WINDOW_SIZE:
            saved = self.settings.value(f"window/size/{ratio_name}")
            if isinstance(saved, QSize) and saved.isValid():
                return saved

        if monitor is None:
            return QSize(*WINDOW_SIZE_FALLBACK_PX)

        # logical size = physical size / scale (what Wayland window sizes are in)
        screen_w, screen_h = monitor[0] / monitor[2], monitor[1] / monitor[2]
        frac_w, frac_h = WINDOW_SIZE_PERCENT.get(ratio_name, WINDOW_SIZE_DEFAULT_PERCENT)

        width = min(screen_w, max(WINDOW_MIN_PX[0], screen_w * frac_w))
        height = min(screen_h, max(WINDOW_MIN_PX[1], screen_h * frac_h))
        return QSize(round(width), round(height))

    # ---- settings ----
    def _load_settings(self):
        s = self.settings
        self._init_sfw = s.value("filters/sfw", True, type=bool)
        self._init_nsfw = s.value("filters/nsfw", True, type=bool)
        if not (self._init_sfw or self._init_nsfw):
            self._init_sfw = self._init_nsfw = True
        self._init_isolate = s.value("filters/isolate_groups", False, type=bool)
        self._init_blur = s.value("view/blur_nsfw", False, type=bool)
        self.preview_enabled = s.value("view/preview", True, type=bool)
        try:
            width = int(s.value("view/thumb_width", THUMB_WIDTH_DEFAULT))
        except (TypeError, ValueError):
            width = THUMB_WIDTH_DEFAULT
        self.thumb_width = max(THUMB_WIDTH_MIN, min(THUMB_WIDTH_MAX, width))
        self._saved_tree_key = None
        try:
            key = json.loads(s.value("tree/key", "", type=str) or "null")
            if isinstance(key, list) and key and all(isinstance(k, str) for k in key):
                self._saved_tree_key = tuple(key)
        except ValueError:
            pass

    def _save_settings(self):
        s = self.settings
        s.setValue("filters/sfw", self.sfw_checkbox.isChecked())
        s.setValue("filters/nsfw", self.nsfw_checkbox.isChecked())
        s.setValue("filters/isolate_groups", self.group_categories_checkbox.isChecked())
        s.setValue("view/blur_nsfw", self.blur_checkbox.isChecked())
        s.setValue("view/preview", self.preview_enabled)
        s.setValue("view/thumb_width", self.thumb_width)
        key = self._selected_tree_key()
        s.setValue("tree/key", json.dumps(list(key)) if key else "")
        if REMEMBER_WINDOW_SIZE:
            s.setValue(f"window/size/{os.path.basename(self.wall_dir)}", self.size())
        s.setValue("window/main_splitter", self.main_splitter.saveState())
        s.sync()

    # ---- convenience ----
    @property
    def all_pictures(self):
        return self.model.paths

    def on_scanning_finished(self, changed):
        if changed or not self._populated:
            self.populate_tree(restore_key=self._selected_tree_key() or self._saved_tree_key,
                               preserve_grid=True)

    def init_ui(self):
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QHBoxLayout(central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        self.main_splitter = QSplitter(Qt.Orientation.Horizontal)
        self.main_splitter.setHandleWidth(1)
        main_layout.addWidget(self.main_splitter)

        # --- LEFT SIDEBAR ---
        sidebar_widget = QWidget()
        sidebar_layout = QVBoxLayout(sidebar_widget)
        sidebar_layout.setContentsMargins(6, 6, 6, 6)
        sidebar_layout.setSpacing(6)

        self.search_bar = QLineEdit()
        self.search_bar.setPlaceholderText("🔍 Search show or character...  (Ctrl+F)")
        self.search_bar.setClearButtonEnabled(True)
        self.search_bar.textChanged.connect(self.on_search_text_changed)
        sidebar_layout.addWidget(self.search_bar)

        toggles_layout = QHBoxLayout()
        toggles_layout.setSpacing(4)

        self.sfw_checkbox = QCheckBox("SFW")
        self.nsfw_checkbox = QCheckBox("NSFW")
        self.group_categories_checkbox = QCheckBox("Isolate group wallpapers")
        self.group_categories_checkbox.setToolTip(
            "Off: a character lists every wallpaper they appear in, groups included.\n"
            "On: group wallpapers (e.g. rem & ram) get their own entry.")
        self.blur_checkbox = QCheckBox("Blur NSFW thumbnails")
        self.blur_checkbox.setToolTip(
            "Blurred wallpapers can't be selected, previewed or applied.  (Ctrl+B)")

        self.sfw_checkbox.setChecked(self._init_sfw)
        self.nsfw_checkbox.setChecked(self._init_nsfw)
        self.group_categories_checkbox.setChecked(self._init_isolate)
        self.blur_checkbox.setChecked(self._init_blur)

        self.sfw_checkbox.stateChanged.connect(self.on_sfw_toggled)
        self.nsfw_checkbox.stateChanged.connect(self.on_nsfw_toggled)
        self.group_categories_checkbox.stateChanged.connect(self.on_group_categories_toggled)
        self.blur_checkbox.toggled.connect(self.on_blur_toggled)

        toggles_layout.addWidget(self.sfw_checkbox)
        toggles_layout.addWidget(self.nsfw_checkbox)
        sidebar_layout.addLayout(toggles_layout)
        sidebar_layout.addWidget(self.group_categories_checkbox)
        sidebar_layout.addWidget(self.blur_checkbox)

        self.tree = QTreeWidget()
        self.tree.setHeaderHidden(True)
        self.tree.setAnimated(True)
        self.tree.setRootIsDecorated(True)
        self.tree.setWordWrap(True)
        self.tree.setStyleSheet("QTreeView::item { padding: 4px; }")
        # itemSelectionChanged covers mouse *and* keyboard navigation
        self.tree.itemSelectionChanged.connect(self.on_tree_selection_changed)
        sidebar_layout.addWidget(self.tree)

        self.main_splitter.addWidget(sidebar_widget)

        # --- RIGHT CONTENT AREA ---
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(8, 8, 8, 8)
        right_layout.setSpacing(8)

        top_bar_layout = QHBoxLayout()
        self.random_btn = QPushButton("🎲 Random Pick")
        self.random_btn.setStyleSheet("font-weight: bold;")
        self.random_btn.setToolTip("Select a random wallpaper from the current list (Ctrl+R)")
        self.random_btn.clicked.connect(self.select_random_wallpaper)
        top_bar_layout.addWidget(self.random_btn)

        self.count_label = QLabel("Loading wallpapers...")
        muted(self.count_label)
        top_bar_layout.addWidget(self.count_label)

        top_bar_layout.addStretch()

        self.size_slider = QSlider(Qt.Orientation.Horizontal)
        self.size_slider.setRange(THUMB_WIDTH_MIN, THUMB_WIDTH_MAX)
        self.size_slider.setSingleStep(20)
        self.size_slider.setPageStep(40)
        self.size_slider.setFixedWidth(110)
        self.size_slider.setValue(self.thumb_width)
        self.size_slider.setToolTip("Thumbnail size  (Ctrl+scroll)")
        self.size_slider.valueChanged.connect(self.on_thumb_size_changed)
        top_bar_layout.addWidget(self.size_slider)

        self.preview_btn = QPushButton("Preview")
        self.preview_btn.setCheckable(True)
        self.preview_btn.setChecked(self.preview_enabled)
        self.preview_btn.setToolTip("Show / hide the preview pane  (Ctrl+P)")
        top_bar_layout.addWidget(self.preview_btn)

        self.apply_btn = QPushButton("Apply")
        self.apply_btn.clicked.connect(self.apply_wallpaper)
        self.cancel_btn = QPushButton("Cancel")
        self.cancel_btn.clicked.connect(self.close)

        top_bar_layout.addWidget(self.apply_btn)
        top_bar_layout.addWidget(self.cancel_btn)
        right_layout.addLayout(top_bar_layout)

        content_splitter = QSplitter(Qt.Orientation.Vertical)
        content_splitter.setHandleWidth(6)
        content_splitter.setStyleSheet(
            "QSplitter::handle { background: transparent; }"
            "QSplitter::handle:hover { background: palette(mid); }")
        right_layout.addWidget(content_splitter)

        grid_container = QWidget()
        grid_layout = QVBoxLayout(grid_container)
        grid_layout.setContentsMargins(0, 0, 0, 0)

        # Model/view instead of 11k QListWidgetItems: filter changes just swap a
        # list of paths and only visible rows ever request a thumbnail.
        self.model = WallpaperModel(self.wall_dir, self.cache_dir, self)
        self.model.set_blur(self._init_blur)

        self.grid_widget = GridView()
        self.grid_widget.setModel(self.model)
        self.grid_widget.setViewMode(QListView.ViewMode.IconMode)
        self.grid_widget.setResizeMode(QListView.ResizeMode.Adjust)
        self.grid_widget.setMovement(QListView.Movement.Static)
        self.grid_widget.setSpacing(10)
        self.grid_widget.setUniformItemSizes(True)
        self.grid_widget.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.grid_widget.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)

        self.grid_widget.setStyleSheet("""
            QListView {
                border-radius: 8px;
                border: 1px solid palette(mid);
                background-color: palette(base);
            }
            QListView::item {
                margin: 6px;
                padding-top: 10px;
                padding-bottom: 6px;
                padding-left: 6px;
                padding-right: 6px;
                border-radius: 6px;
            }
            QListView::item:selected {
                background-color: palette(highlight);
                color: #ffffff;
                border: 1px solid palette(highlight);
            }
            QListView::item:hover {
                background-color: palette(alternate-base);
                border-radius: 6px;
            }
        """)

        self.grid_widget.selectionModel().selectionChanged.connect(self.on_thumbnail_selected)
        self.grid_widget.doubleClicked.connect(lambda _idx: self.apply_wallpaper())
        self.grid_widget.zoomRequested.connect(self.on_zoom_requested)
        self.grid_widget.spacePressed.connect(self.toggle_quick_look)
        grid_layout.addWidget(self.grid_widget)
        content_splitter.addWidget(grid_container)

        self.preview_container = QWidget()
        preview_layout = QVBoxLayout(self.preview_container)
        preview_layout.setContentsMargins(0, 0, 0, 0)
        preview_layout.setSpacing(4)

        self.preview_label = PreviewLabel("Loading wallpapers...")
        self.preview_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview_label.setMinimumHeight(150)
        # Ignore the pixmap's size hint so a big preview can't fight the splitter
        self.preview_label.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Ignored)
        self.preview_label.resized.connect(self.preview_resize_timer.start)
        preview_layout.addWidget(self.preview_label, 1)

        # One quiet line: series · character · resolution
        self.info_label = QLabel("")
        self.info_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        muted(self.info_label, shrink=1)
        preview_layout.addWidget(self.info_label)

        content_splitter.addWidget(self.preview_container)
        content_splitter.setSizes([450, 250])
        self.preview_container.setVisible(self.preview_enabled)
        self.preview_btn.toggled.connect(self.on_preview_toggled)

        self.main_splitter.addWidget(right_widget)
        self.main_splitter.setSizes([280, 970])

        # Quick Look overlay covers the whole window
        self.quick_look = QuickLookOverlay(central_widget)
        self.quick_look.closed.connect(self.close_quick_look)
        self.quick_look.navigate.connect(self.quick_look_navigate)

        splitter_state = self.settings.value("window/main_splitter")
        if splitter_state:
            self.main_splitter.restoreState(splitter_state)

    # ------------------------------------------------------------------
    # Tree
    # ------------------------------------------------------------------
    def _selected_tree_key(self):
        items = self.tree.selectedItems()
        return items[0].data(0, KEY_ROLE) if items else None

    def _visible_count(self, counts):
        sfw, nsfw = self.sfw_checkbox.isChecked(), self.nsfw_checkbox.isChecked()
        return (counts[0] if sfw else 0) + (counts[1] if nsfw else 0)

    def update_tree_counts(self):
        """Refresh the '(N)' suffixes so they match the SFW/NSFW toggles."""
        def apply(item):
            counts, name = item.data(0, COUNT_ROLE), item.data(0, NAME_ROLE)
            if counts is not None:
                item.setText(0, f"{name} ({self._visible_count(counts):,})")

        self.tree.setUpdatesEnabled(False)
        try:
            for i in range(self.tree.topLevelItemCount()):
                top = self.tree.topLevelItem(i)
                apply(top)
                for j in range(top.childCount()):
                    apply(top.child(j))
        finally:
            self.tree.setUpdatesEnabled(True)

    def populate_tree(self, restore_key=None, preserve_grid=False):
        if not os.path.exists(self.db_path):
            return

        isolate = self.group_categories_checkbox.isChecked()

        # One query for the whole tree, counts included
        with closing(sqlite3.connect(self.db_path)) as conn:
            rows = conn.execute(
                "SELECT series, characters, is_nsfw, COUNT(*) FROM wallpapers "
                "WHERE series IS NOT NULL AND substr(path, 1, ?) = ? "
                "GROUP BY series, characters, is_nsfw ORDER BY series, characters",
                self._scope
            ).fetchall()

        items_by_key = {}
        self._tree_updating = True
        self.tree.setUpdatesEnabled(False)
        try:
            self.tree.clear()
            all_counts = [0, 0]
            all_item = QTreeWidgetItem(self.tree, ["All Wallpapers"])
            all_item.setData(0, KEY_ROLE, ("all",))
            all_item.setData(0, NAME_ROLE, "All Wallpapers")
            items_by_key[("all",)] = all_item

            for series, group_rows in groupby(rows, key=lambda r: r[0]):
                series_counts = [0, 0]
                entries = {}
                for _, chars, nsfw, n in group_rows:
                    idx = 1 if nsfw else 0
                    series_counts[idx] += n
                    # Not isolated: every character of a group wallpaper gets it
                    # too (so characters that only appear in groups still show up)
                    for key in ([chars] if isolate else chars.split('-')):
                        entries.setdefault(key, [0, 0])[idx] += n

                series_item = QTreeWidgetItem(self.tree, [""])
                series_key = ("series", series)
                series_item.setData(0, KEY_ROLE, series_key)
                series_item.setData(0, NAME_ROLE, format_single_camel(series))
                series_item.setData(0, COUNT_ROLE, series_counts)
                items_by_key[series_key] = series_item
                all_counts[0] += series_counts[0]
                all_counts[1] += series_counts[1]

                for key in sorted(entries):
                    char_item = QTreeWidgetItem(series_item, [""])
                    char_key = ("char", series, key)
                    char_item.setData(0, KEY_ROLE, char_key)
                    char_item.setData(0, NAME_ROLE, format_character_name(key))
                    char_item.setData(0, COUNT_ROLE, entries[key])
                    items_by_key[char_key] = char_item

            all_item.setData(0, COUNT_ROLE, all_counts)
            self.tree.collapseAll()
            all_item.setExpanded(True)

            target = items_by_key.get(restore_key) if restore_key else None
            if target is None and restore_key and restore_key[0] == "char":
                target = items_by_key.get(("series", restore_key[1]))
            target = target or all_item
            self.tree.setCurrentItem(target)
            if target.parent() is not None:
                target.parent().setExpanded(True)
                self.tree.scrollToItem(target)
        finally:
            self.tree.setUpdatesEnabled(True)
            self._tree_updating = False

        self.update_tree_counts()
        self._populated = True
        self.populate_grid(preserve=preserve_grid)

    def on_tree_selection_changed(self):
        if self._tree_updating:
            return
        if self._filter_state() != self._applied_state:
            self.populate_grid()

    # ------------------------------------------------------------------
    # Search / filters
    # ------------------------------------------------------------------
    def on_search_text_changed(self, text):
        self.search_timer.start()

    def focus_search(self):
        self.search_bar.setFocus()
        self.search_bar.selectAll()

    def _search_terms(self):
        return self.search_bar.text().strip().lower().split()

    def execute_search(self):
        terms = self._search_terms()

        self.tree.setUpdatesEnabled(False)
        try:
            if not terms:
                for i in range(self.tree.topLevelItemCount()):
                    top_item = self.tree.topLevelItem(i)
                    top_item.setHidden(False)
                    for j in range(top_item.childCount()):
                        top_item.child(j).setHidden(False)
                    if i == 0:
                        top_item.setExpanded(True)
                    else:
                        self.tree.collapseItem(top_item)
            else:
                # A search looks at everything: move the selection to "All Wallpapers"
                # so the tree highlight matches what the grid actually shows.
                if self.tree.topLevelItemCount() and self._selected_tree_key() != ("all",):
                    self._tree_updating = True
                    self.tree.setCurrentItem(self.tree.topLevelItem(0))
                    self._tree_updating = False

                for i in range(self.tree.topLevelItemCount()):
                    top_item = self.tree.topLevelItem(i)
                    if i == 0:
                        top_item.setHidden(False)
                        continue

                    series_name = (top_item.data(0, NAME_ROLE) or "").lower()
                    series_matches = all(t in series_name for t in terms)

                    any_char_matched = False
                    for j in range(top_item.childCount()):
                        char_item = top_item.child(j)
                        combined = series_name + " " + (char_item.data(0, NAME_ROLE) or "").lower()
                        if series_matches or all(t in combined for t in terms):
                            char_item.setHidden(False)
                            any_char_matched = True
                        else:
                            char_item.setHidden(True)

                    if series_matches or any_char_matched:
                        top_item.setHidden(False)
                        top_item.setExpanded(True)
                    else:
                        top_item.setHidden(True)
                        self.tree.collapseItem(top_item)
        finally:
            self.tree.setUpdatesEnabled(True)

        self.populate_grid()

    def on_sfw_toggled(self, state):
        if self._updating_checkboxes:
            return
        if not self.sfw_checkbox.isChecked() and not self.nsfw_checkbox.isChecked():
            self._updating_checkboxes = True
            self.nsfw_checkbox.setChecked(True)
            self._updating_checkboxes = False
        self.update_tree_counts()
        self.populate_grid()

    def on_nsfw_toggled(self, state):
        if self._updating_checkboxes:
            return
        if not self.sfw_checkbox.isChecked() and not self.nsfw_checkbox.isChecked():
            self._updating_checkboxes = True
            self.sfw_checkbox.setChecked(True)
            self._updating_checkboxes = False
        self.update_tree_counts()
        self.populate_grid()

    def on_group_categories_toggled(self, state):
        key = self._selected_tree_key()
        if key and key[0] == "char":
            key = ("series", key[1])       # character keys differ between the two modes
        self.populate_tree(restore_key=key)

    def blur_checkbox_toggle(self):
        self.blur_checkbox.toggle()

    def on_blur_toggled(self, checked):
        self.model.set_blur(checked)
        path = self.selected_wallpaper_path
        if checked and path and self.model.is_blocked(path):
            self.grid_widget.clearSelection()
            self._clear_selection_state()

    def _filter_state(self):
        return (
            self._selected_tree_key(),
            self.sfw_checkbox.isChecked(),
            self.nsfw_checkbox.isChecked(),
            self.group_categories_checkbox.isChecked(),
            " ".join(self._search_terms()),
        )

    def get_filtered_pictures(self):
        if not os.path.exists(self.db_path):
            return []

        key = self._selected_tree_key()
        target_series = None
        target_char = None

        # Raw series/character values live on the tree items
        if key:
            if key[0] == "series":
                target_series = key[1]
            elif key[0] == "char":
                target_series, target_char = key[1], key[2]

        prefix_len, prefix = self._scope
        query_conditions = ["substr(path, 1, ?) = ?"]
        query_params = [prefix_len, prefix]

        show_sfw = self.sfw_checkbox.isChecked()
        show_nsfw = self.nsfw_checkbox.isChecked()

        if show_sfw and not show_nsfw:
            query_conditions.append("is_nsfw = 0")
        elif show_nsfw and not show_sfw:
            query_conditions.append("is_nsfw = 1")
        elif not show_sfw and not show_nsfw:
            query_conditions.append("1 = 0")  # return nothing

        if target_series:
            query_conditions.append("series = ?")
            query_params.append(target_series)
        if target_char:
            if self.group_categories_checkbox.isChecked():
                query_conditions.append("characters = ?")
                query_params.append(target_char)
            else:
                # exact name inside "a-b-c" (a plain LIKE '%ram%' also matched "ramen")
                query_conditions.append("instr('-' || characters || '-', ?) > 0")
                query_params.append(f"-{target_char}-")

        # Every search word must appear in series / characters / path *inside* the
        # aspect folder (so "pictures" or "home" no longer match everything)
        for term in self._search_terms():
            query_conditions.append(
                "instr(lower(series || ' ' || characters || ' ' || substr(path, ?)), ?) > 0")
            query_params.extend([prefix_len + 1, term])

        sql = "SELECT path FROM wallpapers WHERE " + " AND ".join(query_conditions)

        with closing(sqlite3.connect(self.db_path)) as conn:
            candidates = [row[0] for row in conn.execute(sql, query_params)]

        candidates.sort(key=natural_sort_key)
        return candidates

    # ------------------------------------------------------------------
    # Grid
    # ------------------------------------------------------------------
    def _get_aspect_ratio(self):
        """Cell aspect ratio, computed once (folders are named "16-9", "21-9", ...)."""
        if self._aspect_ratio:
            return self._aspect_ratio

        m = re.fullmatch(r"(\d+)\s*[-x:]\s*(\d+)", os.path.basename(self.wall_dir))
        if m and int(m.group(2)) > 0 and int(m.group(1)) > 0:
            self._aspect_ratio = int(m.group(1)) / int(m.group(2))
            return self._aspect_ratio

        # Folder isn't named like a ratio: fall back to the first picture, once.
        if self.model.paths:
            size = QImageReader(self.model.paths[0]).size()
            if size.isValid() and size.height() > 0:
                self._aspect_ratio = size.width() / size.height()
                return self._aspect_ratio
        return 16 / 9   # not cached: retry once pictures exist

    def update_grid_layout(self):
        viewport_width = self.grid_widget.viewport().width()
        if viewport_width <= 0:
            return

        aspect_ratio = self._get_aspect_ratio()
        min_thumb_width = self.thumb_width
        spacing = 12

        cols = max(1, viewport_width // (min_thumb_width + spacing))
        item_width = max(min_thumb_width, (viewport_width - (cols * spacing)) // cols)
        item_height = int(item_width / aspect_ratio)

        # setIconSize/setGridSize force a relayout: skip when nothing changed
        layout_key = (item_width, item_height)
        if layout_key == self._layout_key:
            return
        self._layout_key = layout_key

        icon_size = QSize(item_width - 16, item_height - 16)
        self.grid_widget.setIconSize(icon_size)
        self.grid_widget.setGridSize(QSize(item_width, item_height + 40))

        # Cheap neutral tile shown until a thumbnail arrives (keeps cells stable)
        placeholder = QPixmap(icon_size)
        placeholder.fill(self.palette().alternateBase().color())
        self.model.set_icon_size(icon_size, QIcon(placeholder))

    def on_thumb_size_changed(self, value):
        self.thumb_width = value
        self.update_grid_layout()

    def on_zoom_requested(self, direction):
        self.size_slider.setValue(self.thumb_width + 20 * direction)   # slider clamps

    def populate_grid(self, preserve=False):
        pics = self.get_filtered_pictures()

        if preserve and pics == self.model.paths:
            self._applied_state = self._filter_state()
            return      # background rescan changed nothing visible: leave the view alone

        self.model.set_paths(pics)
        self.update_grid_layout()
        self.grid_widget.scrollToTop()
        self._applied_state = self._filter_state()
        self.count_label.setText(f"{len(pics):,} wallpapers")

        # New list -> whatever was selected is no longer on screen
        self._clear_selection_state()

    def select_random_wallpaper(self):
        pics = self.model.paths
        if self.model.blur_enabled:                  # skip wallpapers hidden by the blur
            pics = [p for p in pics if not self.model.is_blocked(p)]
        if not pics:
            QMessageBox.warning(self, "Warning", "No selectable wallpapers in the current selection!")
            return

        row = self.model.row_of(random.choice(pics))
        index = self.model.index(row)
        self.grid_widget.setCurrentIndex(index)
        self.grid_widget.scrollTo(index, QAbstractItemView.ScrollHint.PositionAtCenter)
        self.grid_widget.setFocus()     # Enter applies, Space quick-looks

    # ------------------------------------------------------------------
    # Selection / preview
    # ------------------------------------------------------------------
    def _clear_selection_state(self):
        self.selected_wallpaper_path = None
        self._orig_size = None
        self._preview_seq += 1
        self.preview_timer.stop()
        self._preview_src = None
        self.preview_label.setText("Select a wallpaper to preview")
        self.info_label.setText("")
        if self.quick_look.isVisible():
            self.close_quick_look()

    def _screen_pixels(self):
        screen = self.screen()
        if not screen:
            return None
        size, dpr = screen.size(), screen.devicePixelRatio()
        return round(size.width() * dpr), round(size.height() * dpr)

    def _caption_for(self, path):
        rel = os.path.relpath(path, self.wall_dir)
        _, chars = parse_wallpaper_name(os.path.basename(path))
        text = html.escape(f"{format_single_camel(rel.split(os.sep)[0])} · "
                           f"{format_character_name('-'.join(chars))}")
        size = self._orig_size
        if size is not None and size.isValid():
            res = f"{size.width()}×{size.height()}"
            screen = self._screen_pixels()
            # Only speak up when the file would have to be *upscaled* for this screen
            if screen and (size.width() < screen[0] or size.height() < screen[1]):
                text += f' · <span style="color:#d9a441">{res} (below screen resolution)</span>'
            else:
                text += f" · {res}"
        return text

    def _refresh_captions(self):
        if not self.selected_wallpaper_path:
            return
        text = self._caption_for(self.selected_wallpaper_path)
        self.info_label.setText(text)
        if self.quick_look.isVisible():
            self.quick_look.set_caption(text)

    def on_thumbnail_selected(self, *args):
        indexes = self.grid_widget.selectionModel().selectedIndexes()
        if not indexes:
            if self.selected_wallpaper_path:
                self._clear_selection_state()
            return

        pic_path = indexes[0].data(Qt.ItemDataRole.UserRole)
        if self.model.is_blocked(pic_path):
            return
        self.selected_wallpaper_path = pic_path
        self._orig_size = None
        self._ql_has_full = False
        self._preview_seq += 1      # invalidates any decode still in flight
        self._refresh_captions()

        # Instant feedback: show the (already decoded) thumbnail, then swap in the
        # sharper version once the background decode finishes.
        cached = self.model.cached_pixmap(pic_path)
        if cached is not None:
            self._preview_src = cached.toImage()
            self._render_preview()
            if self.quick_look.isVisible():
                self.quick_look.set_image(self._preview_src)

        self.preview_timer.start()   # debounced: skips files passed over with arrow keys

    def _start_preview_job(self):
        path = self.selected_wallpaper_path
        if not path:
            return
        seq = self._preview_seq
        if self.preview_enabled:
            self.preview_pool.clear()
            self.preview_pool.start(PreviewJob(path, seq, PREVIEW_MAX, self.preview_signals))
        if self.quick_look.isVisible():
            self.ql_pool.clear()
            self.ql_pool.start(PreviewJob(path, seq, QUICKLOOK_MAX, self.ql_signals))

    @pyqtSlot(int, QImage, QSize)
    def _on_preview_decoded(self, seq, image, orig_size):
        if seq != self._preview_seq or image.isNull():
            return
        if orig_size.isValid():
            self._orig_size = orig_size
            self._refresh_captions()
        self._preview_src = image
        self._render_preview()
        if self.quick_look.isVisible() and not self._ql_has_full:
            self.quick_look.set_image(image)

    @pyqtSlot(int, QImage, QSize)
    def _on_quicklook_decoded(self, seq, image, orig_size):
        if seq != self._preview_seq or image.isNull() or not self.quick_look.isVisible():
            return
        if orig_size.isValid() and self._orig_size is None:
            self._orig_size = orig_size
            self._refresh_captions()
        self._ql_has_full = True
        self.quick_look.set_image(image)

    def _render_preview(self):
        """Scale the already-decoded preview image to the label (no disk access)."""
        if self._preview_src is None or self._preview_src.isNull():
            return
        dpr = self.devicePixelRatioF()
        target = self.preview_label.size() * dpr
        if target.isEmpty():
            return
        scaled = self._preview_src.scaled(
            target, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation
        )
        pixmap = QPixmap.fromImage(scaled)
        pixmap.setDevicePixelRatio(dpr)
        self.preview_label.setPixmap(pixmap)

    def preview_btn_toggle(self):
        self.preview_btn.toggle()

    def on_preview_toggled(self, checked):
        self.preview_enabled = checked
        self.preview_container.setVisible(checked)
        if checked and self.selected_wallpaper_path:
            cached = self.model.cached_pixmap(self.selected_wallpaper_path)
            if self._preview_src is None and cached is not None:
                self._preview_src = cached.toImage()
            self._render_preview()
            self._start_preview_job()

    # ------------------------------------------------------------------
    # Quick Look
    # ------------------------------------------------------------------
    def toggle_quick_look(self):
        if self.quick_look.isVisible():
            self.close_quick_look()
            return

        if not self.selected_wallpaper_path:
            # nothing selected yet: select the focused cell, if it can be selected
            idx = self.grid_widget.currentIndex()
            if idx.isValid() and (self.model.flags(idx) & Qt.ItemFlag.ItemIsSelectable):
                self.grid_widget.setCurrentIndex(idx)
        if not self.selected_wallpaper_path:
            return

        self.quick_look.setGeometry(self.centralWidget().rect())
        self.quick_look.raise_()
        self._ql_has_full = False
        self.quick_look.set_caption(self._caption_for(self.selected_wallpaper_path))
        if self._preview_src is not None:
            self.quick_look.set_image(self._preview_src)
        self.quick_look.show()
        self.quick_look.setFocus()
        self._start_preview_job()

    def close_quick_look(self):
        self.ql_pool.clear()
        self.quick_look.hide()
        self.grid_widget.setFocus()

    def quick_look_navigate(self, step):
        cur = self.grid_widget.currentIndex()
        row = self.model.next_selectable(cur.row() if cur.isValid() else -1, step)
        if row is not None:
            idx = self.model.index(row)
            self.grid_widget.setCurrentIndex(idx)
            self.grid_widget.scrollTo(idx)

    # ------------------------------------------------------------------
    # Window events
    # ------------------------------------------------------------------
    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.update_grid_layout()
        if self.quick_look.isVisible():
            self.quick_look.setGeometry(self.centralWidget().rect())

    def keyPressEvent(self, event):
        if event.key() == Qt.Key.Key_Escape:
            if self.quick_look.isVisible():
                self.close_quick_look()
            elif self.search_bar.hasFocus() and self.search_bar.text():
                self.search_bar.clear()
            else:
                self.close()
        else:
            super().keyPressEvent(event)

    def on_enter_pressed(self):
        if self.search_bar.hasFocus():
            # Enter in the search box: show the results and move into the grid
            if self.search_timer.isActive():
                self.search_timer.stop()
                self.execute_search()
            if not self.selected_wallpaper_path:
                row = self.model.next_selectable(-1, 1)
                if row is not None:
                    self.grid_widget.setCurrentIndex(self.model.index(row))
            self.grid_widget.setFocus()
            return
        self.apply_wallpaper()

    def closeEvent(self, event):
        self._save_settings()
        # Stop background work cleanly (avoids "QThread destroyed while running")
        self.scanner_thread.abort()
        self.model.shutdown()
        for pool in (self.preview_pool, self.ql_pool):
            pool.clear()
            pool.waitForDone(2000)
        self.scanner_thread.wait(3000)
        super().closeEvent(event)

    def apply_wallpaper(self):
        path = self.selected_wallpaper_path
        if not path:
            QMessageBox.warning(self, "Warning", "Please select a wallpaper first!")
            return
        if self.model.is_blocked(path):
            QMessageBox.warning(self, "Warning", "That wallpaper is hidden by the NSFW blur.")
            return

        # The applicator wants the path relative to the aspect folder ("/series/file.png")
        rel_path = "/" + os.path.relpath(path, self.wall_dir)

        applicator_wayland = os.path.expanduser("~/.config/WallpaperChanger/WallpaperApplicator.sh")
        applicator_xrandr = os.path.expanduser("~/.config/WallpaperChanger/WallpaperApplicatorXrandr.sh")

        applicator_script = None
        if os.path.exists(applicator_wayland):
            applicator_script = applicator_wayland
        elif os.path.exists(applicator_xrandr):
            applicator_script = applicator_xrandr

        if not applicator_script:
            QMessageBox.critical(self, "Error", "No WallpaperApplicator script found on the system!")
            return
        if not os.access(applicator_script, os.X_OK):
            QMessageBox.critical(self, "Error", f"{applicator_script} is not executable!")
            return

        self.hide()
        self.close()
        QApplication.processEvents()

        try:
            # own session: the applicator keeps running after the GUI is gone, even
            # if the GUI was started from a terminal/wrapper that cleans up its children
            subprocess.Popen([applicator_script, rel_path], start_new_session=True)
        except OSError as exc:
            print(f"Could not start {applicator_script}: {exc}", file=sys.stderr)
        QApplication.quit()


if __name__ == "__main__":
    app = QApplication(sys.argv)
    # Stable window class / Wayland app_id for compositor window rules (the title
    # changes with the aspect folder, so don't match on it)
    app.setApplicationName("wallpaper-selector")
    QGuiApplication.setDesktopFileName("wallpaper-selector")
    window = WallpaperApp(aspect_override=sys.argv[1] if len(sys.argv) > 1 else None)
    window.show()
    sys.exit(app.exec())