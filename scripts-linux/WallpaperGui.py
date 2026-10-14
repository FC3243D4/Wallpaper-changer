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
    QObject, QAbstractListModel, QModelIndex, pyqtSignal, pyqtSlot
)
from PyQt6.QtGui import (
    QPixmap, QIcon, QImage, QImageReader, QKeySequence, QShortcut, QPixmapCache
)
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QHBoxLayout, QVBoxLayout,
    QTreeWidget, QTreeWidgetItem, QLabel, QListView, QAbstractItemView,
    QPushButton, QCheckBox, QSplitter, QMessageBox, QWidget, QLineEdit,
    QSizePolicy
)

# Suppress harmless Wayland text-input warnings
QLoggingCategory.setFilterRules("qt.qpa.wayland.textinput.warning=false")

THUMB_MAX = 600                       # longest side of a cached thumbnail
PREVIEW_MAX = 2560                    # longest side the preview is decoded at
THUMB_MEMORY_BUDGET = 192 * 1024**2   # decoded thumbnails kept in RAM (bytes)
IMAGE_EXTS = ('png', 'jpg', 'jpeg')


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
    (JPEG does it in the DCT domain) instead of decoding the full 4K bitmap and
    scaling afterwards. Works on QImage, so it is safe to call off the GUI thread.
    """
    reader = QImageReader(path)
    size = reader.size()
    if size.isValid() and (size.width() > max_dim or size.height() > max_dim):
        size.scale(max_dim, max_dim, Qt.AspectRatioMode.KeepAspectRatio)
        reader.setScaledSize(size)
    return reader.read()


def load_or_make_thumbnail(src, thumb_path):
    """Return the thumbnail as a QImage, generating + caching it if needed."""
    try:
        if os.path.getmtime(thumb_path) >= os.path.getmtime(src):
            img = QImage(thumb_path)
            if not img.isNull():
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


# --------------------------------------------------------------------------
# Background workers
# --------------------------------------------------------------------------
class WallpaperScannerWorker(QThread):
    # (named scan_done, not "finished", so it no longer shadows QThread.finished)
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

        conn = sqlite3.connect(self.db_path)
        try:
            ensure_schema(conn)

            # Existing paths + mtimes for fast incremental checks
            db_records = dict(conn.execute("SELECT path, mtime FROM wallpapers"))

            disk_paths = set()
            batch_data = []

            for series, f, full_path, mtime in self._iter_images():
                disk_paths.add(full_path)

                # Already indexed and unchanged -> skip parsing
                if db_records.get(full_path) == mtime:
                    continue

                name_without_ext = os.path.splitext(f)[0]
                is_nsfw = 1 if name_without_ext.lower().startswith("nsfw-") else 0
                clean_name = name_without_ext[5:] if is_nsfw else name_without_ext
                parts = [c.strip() for c in clean_name.split('-') if c.strip()]

                characters = [c for c in parts if not c.isdigit()]
                if not characters:
                    characters = ["General"]

                char_key = "-".join(characters)
                is_group = 1 if len(characters) > 1 else 0

                batch_data.append((full_path, series, char_key, is_nsfw, is_group, mtime))

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
    ready = pyqtSignal(int, QImage)


class PreviewJob(QRunnable):
    def __init__(self, path, seq, signals):
        super().__init__()
        self.path = path
        self.seq = seq
        self.signals = signals

    def run(self):
        img = QImage()
        try:
            img = read_scaled(self.path, PREVIEW_MAX)
        except Exception:
            pass
        self.signals.ready.emit(self.seq, img)


# --------------------------------------------------------------------------
# Model: holds only the list of paths; thumbnails are loaded lazily for the
# rows that are actually painted.
# --------------------------------------------------------------------------
class ThumbCache:
    """Byte-budgeted LRU of decoded thumbnails (GUI thread only)."""

    def __init__(self, max_bytes):
        self._items = OrderedDict()   # path -> (pixmap, icon, nbytes)
        self._bytes = 0
        self._max = max_bytes

    def get(self, key):
        item = self._items.get(key)
        if item is not None:
            self._items.move_to_end(key)
        return item

    def put(self, key, pixmap):
        nbytes = pixmap.width() * pixmap.height() * 4
        old = self._items.pop(key, None)
        if old:
            self._bytes -= old[2]
        self._items[key] = (pixmap, QIcon(pixmap), nbytes)
        self._bytes += nbytes
        while self._bytes > self._max and len(self._items) > 1:
            _, (_, _, n) = self._items.popitem(last=False)
            self._bytes -= n


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

    def set_placeholder(self, icon):
        self._placeholder = icon

    def cached_pixmap(self, path):
        item = self._cache.get(path)
        return item[0] if item else None

    def shutdown(self):
        self._pool.clear()
        self._pool.waitForDone(2000)

    # --- Qt model interface ---
    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self.paths)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid():
            return None
        path = self.paths[index.row()]

        if role == Qt.ItemDataRole.DisplayRole:
            return os.path.basename(path)
        if role == Qt.ItemDataRole.UserRole:
            return path
        if role == Qt.ItemDataRole.DecorationRole:
            item = self._cache.get(path)
            if item is not None:
                return item[1]
            self._request(path)
            return self._placeholder
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


class PreviewLabel(QLabel):
    resized = pyqtSignal()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.resized.emit()


# --------------------------------------------------------------------------
# Main window
# --------------------------------------------------------------------------
class WallpaperApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Wallpaper Selector")
        self.resize(1300, 850)

        # Scaled icons are cached by Qt in QPixmapCache (default ~10 MB), which is
        # smaller than one screenful of thumbnails -> constant re-scaling on paint.
        QPixmapCache.setCacheLimit(128 * 1024)

        self.wall_base_dir = os.path.expanduser("~/Pictures/wallpapers")
        if os.path.isdir(os.path.join(self.wall_base_dir, "16-9")):
            self.wall_dir = os.path.join(self.wall_base_dir, "16-9")
        else:
            subdirs = sorted([os.path.join(self.wall_base_dir, d) for d in os.listdir(self.wall_base_dir) if os.path.isdir(os.path.join(self.wall_base_dir, d))])
            self.wall_dir = subdirs[0] if subdirs else self.wall_base_dir

        self.cache_dir = os.path.expanduser("~/.cache/wallpaper-thumbnails")
        self.db_path = os.path.expanduser("~/.cache/wallpaper-changer.db")
        os.makedirs(self.cache_dir, exist_ok=True)

        self.selected_wallpaper_path = None
        self._updating_checkboxes = False
        self._populated = False
        self._applied_state = None
        self._aspect_ratio = None
        self._layout_key = None

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

        # Keyboard shortcuts for Enter / Return to apply wallpaper instantly
        self.enter_shortcut_1 = QShortcut(QKeySequence(Qt.Key.Key_Return), self)
        self.enter_shortcut_1.activated.connect(self.apply_wallpaper)
        self.enter_shortcut_2 = QShortcut(QKeySequence(Qt.Key.Key_Enter), self)
        self.enter_shortcut_2.activated.connect(self.apply_wallpaper)

        # 1. Build UI instantly
        self.init_ui()

        # 2. Show whatever the index already knows *right now*; the scan below
        #    only refreshes it if something actually changed on disk.
        with closing(sqlite3.connect(self.db_path)) as conn:
            ensure_schema(conn)
            has_rows = conn.execute("SELECT 1 FROM wallpapers LIMIT 1").fetchone() is not None
        if has_rows:
            self.populate_tree()

        # 3. Run incremental scanner worker in background thread
        self.scanner_thread = WallpaperScannerWorker(self.wall_dir, self.db_path)
        self.scanner_thread.scan_done.connect(self.on_scanning_finished)
        self.scanner_thread.start()

    # ---- convenience ----
    @property
    def all_pictures(self):
        return self.model.paths

    def on_scanning_finished(self, changed):
        if changed or not self._populated:
            self.populate_tree(restore_key=self._selected_tree_key(), preserve_grid=True)

    def init_ui(self):
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QHBoxLayout(central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        main_splitter = QSplitter(Qt.Orientation.Horizontal)
        main_splitter.setHandleWidth(1)
        main_layout.addWidget(main_splitter)

        # --- LEFT SIDEBAR ---
        sidebar_widget = QWidget()
        sidebar_layout = QVBoxLayout(sidebar_widget)
        sidebar_layout.setContentsMargins(6, 6, 6, 6)
        sidebar_layout.setSpacing(6)

        self.search_bar = QLineEdit()
        self.search_bar.setPlaceholderText("🔍 Search show or character...")
        self.search_bar.textChanged.connect(self.on_search_text_changed)
        sidebar_layout.addWidget(self.search_bar)

        toggles_layout = QHBoxLayout()
        toggles_layout.setSpacing(4)

        self.sfw_checkbox = QCheckBox("SFW")
        self.nsfw_checkbox = QCheckBox("NSFW")
        self.group_categories_checkbox = QCheckBox("Group Categories")

        self.sfw_checkbox.setChecked(True)
        self.nsfw_checkbox.setChecked(True)
        self.group_categories_checkbox.setChecked(False)

        self.sfw_checkbox.stateChanged.connect(self.on_sfw_toggled)
        self.nsfw_checkbox.stateChanged.connect(self.on_nsfw_toggled)
        self.group_categories_checkbox.stateChanged.connect(self.on_group_categories_toggled)

        toggles_layout.addWidget(self.sfw_checkbox)
        toggles_layout.addWidget(self.nsfw_checkbox)
        sidebar_layout.addLayout(toggles_layout)
        sidebar_layout.addWidget(self.group_categories_checkbox)

        self.tree = QTreeWidget()
        self.tree.setHeaderHidden(True)
        self.tree.setAnimated(True)
        self.tree.setRootIsDecorated(True)
        self.tree.setWordWrap(True)
        self.tree.setStyleSheet("QTreeView::item { padding: 4px; }")
        self.tree.itemClicked.connect(self.on_tree_item_clicked)
        sidebar_layout.addWidget(self.tree)

        main_splitter.addWidget(sidebar_widget)

        # --- RIGHT CONTENT AREA ---
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(8, 8, 8, 8)
        right_layout.setSpacing(8)

        top_bar_layout = QHBoxLayout()
        self.random_btn = QPushButton("🎲 Random Pick")
        self.random_btn.setStyleSheet("font-weight: bold;")
        self.random_btn.clicked.connect(self.select_random_wallpaper)
        top_bar_layout.addWidget(self.random_btn)

        top_bar_layout.addStretch()

        self.apply_btn = QPushButton("Apply")
        self.apply_btn.clicked.connect(self.apply_wallpaper)
        self.cancel_btn = QPushButton("Cancel")
        self.cancel_btn.clicked.connect(self.close)

        top_bar_layout.addWidget(self.apply_btn)
        top_bar_layout.addWidget(self.cancel_btn)
        right_layout.addLayout(top_bar_layout)

        content_splitter = QSplitter(Qt.Orientation.Vertical)
        content_splitter.setHandleWidth(0)
        content_splitter.setStyleSheet("QSplitter::handle { background: transparent; }")
        right_layout.addWidget(content_splitter)

        grid_container = QWidget()
        grid_layout = QVBoxLayout(grid_container)
        grid_layout.setContentsMargins(0, 0, 0, 0)

        # Model/view instead of 11k QListWidgetItems: filter changes just swap a
        # list of paths and only visible rows ever request a thumbnail.
        self.model = WallpaperModel(self.wall_dir, self.cache_dir, self)

        self.grid_widget = QListView()
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
        grid_layout.addWidget(self.grid_widget)
        content_splitter.addWidget(grid_container)

        preview_container = QWidget()
        preview_layout = QVBoxLayout(preview_container)
        preview_layout.setContentsMargins(0, 0, 0, 0)

        self.preview_label = PreviewLabel("Loading wallpapers...")
        self.preview_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview_label.setMinimumHeight(150)
        # Ignore the pixmap's size hint so a big preview can't fight the splitter
        self.preview_label.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Ignored)
        self.preview_label.resized.connect(self.preview_resize_timer.start)
        preview_layout.addWidget(self.preview_label)

        content_splitter.addWidget(preview_container)
        content_splitter.setSizes([450, 250])

        main_splitter.addWidget(right_widget)
        main_splitter.setSizes([280, 970])

    # ------------------------------------------------------------------
    # Tree
    # ------------------------------------------------------------------
    def _selected_tree_key(self):
        items = self.tree.selectedItems()
        return items[0].data(0, Qt.ItemDataRole.UserRole) if items else None

    def populate_tree(self, restore_key=None, preserve_grid=False):
        if not os.path.exists(self.db_path):
            return

        separate_groups = self.group_categories_checkbox.isChecked()

        # One query instead of one per series
        with closing(sqlite3.connect(self.db_path)) as conn:
            rows = conn.execute(
                "SELECT DISTINCT series, characters, is_group FROM wallpapers "
                "WHERE series IS NOT NULL ORDER BY series, characters"
            ).fetchall()

        items_by_key = {}
        self.tree.setUpdatesEnabled(False)
        try:
            self.tree.clear()
            all_items_root = QTreeWidgetItem(self.tree, ["All Wallpapers"])
            all_items_root.setData(0, Qt.ItemDataRole.UserRole, ("all",))
            items_by_key[("all",)] = all_items_root

            for series, group_rows in groupby(rows, key=lambda r: r[0]):
                series_item = QTreeWidgetItem(self.tree, [format_single_camel(series)])
                series_key = ("series", series)
                series_item.setData(0, Qt.ItemDataRole.UserRole, series_key)
                items_by_key[series_key] = series_item

                for _, char_group_str, is_group in group_rows:
                    if separate_groups:
                        entries = [(char_group_str, format_character_name(char_group_str))]
                    elif is_group:
                        continue
                    else:
                        entries = [(c, format_character_name(c)) for c in char_group_str.split('-')]

                    for raw, display in entries:
                        char_item = QTreeWidgetItem(series_item, [display])
                        char_key = ("char", series, raw)
                        char_item.setData(0, Qt.ItemDataRole.UserRole, char_key)
                        items_by_key.setdefault(char_key, char_item)

            self.tree.collapseAll()
            all_items_root.setExpanded(True)

            target = items_by_key.get(restore_key) if restore_key else None
            (target or all_items_root).setSelected(True)
            if target is not None and target.parent() is not None:
                target.parent().setExpanded(True)
                self.tree.scrollToItem(target)
        finally:
            self.tree.setUpdatesEnabled(True)

        self._populated = True
        self.populate_grid(preserve=preserve_grid)

    # ------------------------------------------------------------------
    # Search / filters
    # ------------------------------------------------------------------
    def on_search_text_changed(self, text):
        self.search_timer.start()

    def execute_search(self):
        query = self.search_bar.text().strip().lower()

        self.tree.setUpdatesEnabled(False)
        try:
            if not query:
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
                for i in range(self.tree.topLevelItemCount()):
                    top_item = self.tree.topLevelItem(i)
                    if i == 0:
                        top_item.setHidden(False)
                        continue

                    series_matches = query in top_item.text(0).lower()

                    any_char_matched = False
                    for j in range(top_item.childCount()):
                        char_item = top_item.child(j)
                        if series_matches or query in char_item.text(0).lower():
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
        self.populate_grid()

    def on_nsfw_toggled(self, state):
        if self._updating_checkboxes:
            return
        if not self.sfw_checkbox.isChecked() and not self.nsfw_checkbox.isChecked():
            self._updating_checkboxes = True
            self.sfw_checkbox.setChecked(True)
            self._updating_checkboxes = False
        self.populate_grid()

    def on_group_categories_toggled(self, state):
        self.populate_tree()

    def _filter_state(self):
        return (
            self._selected_tree_key(),
            self.sfw_checkbox.isChecked(),
            self.nsfw_checkbox.isChecked(),
            self.group_categories_checkbox.isChecked(),
            self.search_bar.text().strip().lower(),
        )

    def get_filtered_pictures(self):
        if not os.path.exists(self.db_path):
            return []

        search_query = self.search_bar.text().strip().lower()
        key = self._selected_tree_key()
        target_series = None
        target_char = None

        # Raw series/character values live on the tree items, so no DB lookups
        # or display-name reverse matching are needed here anymore.
        if key:
            if key[0] == "series":
                target_series = key[1]
            elif key[0] == "char":
                target_series, target_char = key[1], key[2]

        query_conditions = []
        query_params = []

        show_sfw = self.sfw_checkbox.isChecked()
        show_nsfw = self.nsfw_checkbox.isChecked()

        if show_sfw and not show_nsfw:
            query_conditions.append("is_nsfw = 0")
        elif show_nsfw and not show_sfw:
            query_conditions.append("is_nsfw = 1")
        elif not show_sfw and not show_nsfw:
            query_conditions.append("1 = 0")  # return nothing

        separate_groups = self.group_categories_checkbox.isChecked()

        if target_series and target_char:
            query_conditions.append("series = ?")
            query_params.append(target_series)
            if separate_groups:
                query_conditions.append("characters = ?")
                query_params.append(target_char)
            else:
                query_conditions.append("characters LIKE ?")
                query_params.append(f"%{target_char}%")
        elif target_series and not target_char:
            query_conditions.append("series = ?")
            query_params.append(target_series)

        if search_query:
            query_conditions.append("(series LIKE ? OR characters LIKE ? OR path LIKE ?)")
            query_params.extend([f"%{search_query}%", f"%{search_query}%", f"%{search_query}%"])

        sql = "SELECT path FROM wallpapers"
        if query_conditions:
            sql += " WHERE " + " AND ".join(query_conditions)

        with closing(sqlite3.connect(self.db_path)) as conn:
            candidates = [row[0] for row in conn.execute(sql, query_params)]

        candidates.sort(key=natural_sort_key)   # path is the primary key: already unique
        return candidates

    # ------------------------------------------------------------------
    # Grid
    # ------------------------------------------------------------------
    def _get_aspect_ratio(self):
        """Cell aspect ratio, computed once.

        The collection is organised in folders named after their aspect ratio
        ("16-9", "21-9", ...), so the ratio comes from the folder name and no image
        header has to be read (the old code opened the first picture on every
        resize/populate).
        """
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
        min_thumb_width = 280
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
        self.model.set_placeholder(QIcon(placeholder))

    def populate_grid(self, preserve=False):
        pics = self.get_filtered_pictures()

        if preserve and pics == self.model.paths:
            self._applied_state = self._filter_state()
            return      # background rescan changed nothing visible: leave the view alone

        self.model.set_paths(pics)
        self.update_grid_layout()
        self.grid_widget.scrollToTop()
        self._applied_state = self._filter_state()

        # New list -> previous preview no longer matches anything on screen
        self.preview_timer.stop()
        self._preview_seq += 1
        self._preview_src = None
        self.preview_label.setPixmap(QPixmap())
        self.preview_label.setText("Select a wallpaper to preview")

    def select_random_wallpaper(self):
        pics = self.model.paths
        if not pics:
            QMessageBox.warning(self, "Warning", "No wallpapers available in the current selection!")
            return

        row = self.model.row_of(random.choice(pics))
        index = self.model.index(row)
        self.grid_widget.setCurrentIndex(index)
        self.grid_widget.scrollTo(index)

    def on_tree_item_clicked(self, item, column):
        if self._filter_state() == self._applied_state:
            return      # same node clicked again: don't rebuild the grid
        self.populate_grid()

    # ------------------------------------------------------------------
    # Preview
    # ------------------------------------------------------------------
    def on_thumbnail_selected(self, *args):
        indexes = self.grid_widget.selectionModel().selectedIndexes()
        if not indexes:
            return

        pic_path = indexes[0].data(Qt.ItemDataRole.UserRole)
        self.selected_wallpaper_path = pic_path
        self._preview_seq += 1      # invalidates any decode still in flight

        # Instant feedback: show the (already decoded) thumbnail, then swap in the
        # sharper version once the background decode finishes.
        cached = self.model.cached_pixmap(pic_path)
        if cached is not None:
            self._preview_src = cached.toImage()
            self._render_preview()

        self.preview_timer.start()   # debounced: skips files passed over with arrow keys

    def _start_preview_job(self):
        path = self.selected_wallpaper_path
        if not path:
            return
        self.preview_pool.clear()
        self.preview_pool.start(PreviewJob(path, self._preview_seq, self.preview_signals))

    @pyqtSlot(int, QImage)
    def _on_preview_decoded(self, seq, image):
        if seq != self._preview_seq or image.isNull():
            return
        self._preview_src = image
        self._render_preview()

    def _render_preview(self):
        """Scale the already-decoded preview image to the label (no disk access)."""
        if self._preview_src is None or self._preview_src.isNull():
            return
        dpr = self.devicePixelRatioF()
        target = self.preview_label.size() * dpr
        if target.width() <= 0 or target.height() <= 0:
            return
        scaled = self._preview_src.scaled(
            target, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation
        )
        pixmap = QPixmap.fromImage(scaled)
        pixmap.setDevicePixelRatio(dpr)
        self.preview_label.setPixmap(pixmap)

    # ------------------------------------------------------------------
    # Window events
    # ------------------------------------------------------------------
    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.update_grid_layout()

    def keyPressEvent(self, event):
        if event.key() == Qt.Key.Key_Escape:
            self.close()
        else:
            super().keyPressEvent(event)

    def closeEvent(self, event):
        # Stop background work cleanly (avoids "QThread destroyed while running")
        self.scanner_thread.abort()
        self.model.shutdown()
        self.preview_pool.clear()
        self.preview_pool.waitForDone(2000)
        self.scanner_thread.wait(3000)
        super().closeEvent(event)

    def apply_wallpaper(self):
        if not self.selected_wallpaper_path:
            QMessageBox.warning(self, "Warning", "Please select a wallpaper first!")
            return

        rel_path = self.selected_wallpaper_path
        if self.wall_base_dir in rel_path:
            rel_path = rel_path.replace(self.wall_base_dir, "")
            parts = rel_path.strip("/").split("/")
            if len(parts) > 1:
                rel_path = "/" + "/".join(parts[1:])
            else:
                rel_path = "/" + "/".join(parts)

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

        self.hide()
        self.close()
        QApplication.processEvents()

        subprocess.Popen([applicator_script, rel_path])
        sys.exit(0)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = WallpaperApp()
    window.show()
    sys.exit(app.exec())