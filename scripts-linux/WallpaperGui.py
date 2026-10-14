import os
import random
import re
import sys
import sqlite3
import subprocess
from PyQt6.QtCore import Qt, QSize, QLoggingCategory, QTimer, QThread, pyqtSignal
from PyQt6.QtGui import QPixmap, QIcon, QImageReader, QKeySequence, QShortcut
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QHBoxLayout, QVBoxLayout,
    QTreeWidget, QTreeWidgetItem, QLabel, QListWidget, QListWidgetItem,
    QPushButton, QCheckBox, QSplitter, QMessageBox, QWidget, QLineEdit
)

# Suppress harmless Wayland text-input warnings
QLoggingCategory.setFilterRules("qt.qpa.wayland.textinput.warning=false")

def natural_sort_key(s):
    return [int(text) if text.isdigit() else text.lower() for text in re.split(r'(\d+)', s)]

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


class WallpaperScannerWorker(QThread):
    finished = pyqtSignal()

    def __init__(self, wall_dir, db_path):
        super().__init__()
        self.wall_dir = wall_dir
        self.db_path = db_path

    def run(self):
        if not os.path.exists(self.wall_dir):
            self.finished.emit()
            return

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS wallpapers (
                path TEXT PRIMARY KEY,
                series TEXT,
                characters TEXT,
                is_nsfw INTEGER,
                is_group INTEGER,
                mtime REAL
            )
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_series ON wallpapers(series)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_nsfw ON wallpapers(is_nsfw)")
        conn.commit()

        # Get existing paths and mtimes from DB for fast incremental checks
        cursor.execute("SELECT path, mtime FROM wallpapers")
        db_records = {row[0]: row[1] for row in cursor.fetchall()}

        disk_paths = set()
        batch_data = []

        for series in os.listdir(self.wall_dir):
            series_path = os.path.join(self.wall_dir, series)
            if not os.path.isdir(series_path):
                continue

            for root, dirs, files in os.walk(series_path):
                for f in files:
                    if not f.lower().endswith(('png', 'jpg', 'jpeg')):
                        continue
                    
                    full_path = os.path.join(root, f)
                    try:
                        mtime = os.path.getmtime(full_path)
                    except OSError:
                        continue

                    disk_paths.add(full_path)

                    # If file is already indexed and hasn't changed, skip parsing
                    if full_path in db_records and db_records[full_path] == mtime:
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

        # Perform incremental batch update
        if batch_data:
            cursor.executemany("""
                INSERT OR REPLACE INTO wallpapers (path, series, characters, is_nsfw, is_group, mtime)
                VALUES (?, ?, ?, ?, ?, ?)
            """, batch_data)

        # Remove deleted files from DB
        deleted_paths = set(db_records.keys()) - disk_paths
        if deleted_paths:
            cursor.executemany("DELETE FROM wallpapers WHERE path = ?", [(p,) for p in deleted_paths])

        conn.commit()
        conn.close()
        self.finished.emit()


class WallpaperApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Wallpaper Selector")
        self.resize(1300, 850)

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
        self.all_pictures = []
        self._updating_checkboxes = False
        self.display_to_raw_key = {}

        # Debounce timer for smooth typing
        self.search_timer = QTimer()
        self.search_timer.setSingleShot(True)
        self.search_timer.setInterval(300)
        self.search_timer.timeout.connect(self.execute_search)

        # Keyboard shortcuts for Enter / Return to apply wallpaper instantly
        self.enter_shortcut_1 = QShortcut(QKeySequence(Qt.Key.Key_Return), self)
        self.enter_shortcut_1.activated.connect(self.apply_wallpaper)
        self.enter_shortcut_2 = QShortcut(QKeySequence(Qt.Key.Key_Enter), self)
        self.enter_shortcut_2.activated.connect(self.apply_wallpaper)

        # 1. Build UI instantly
        self.init_ui()

        # 2. Run incremental scanner worker in background thread
        self.scanner_thread = WallpaperScannerWorker(self.wall_dir, self.db_path)
        self.scanner_thread.finished.connect(self.on_scanning_finished)
        self.scanner_thread.start()

    def on_scanning_finished(self):
        self.populate_tree()

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

        self.grid_widget = QListWidget()
        self.grid_widget.setViewMode(QListWidget.ViewMode.IconMode)
        self.grid_widget.setResizeMode(QListWidget.ResizeMode.Adjust)
        self.grid_widget.setMovement(QListWidget.Movement.Static)
        self.grid_widget.setSpacing(10)
        
        self.grid_widget.setStyleSheet("""
            QListWidget {
                border-radius: 8px;
                border: 1px solid palette(mid);
                background-color: palette(base);
            }
            QListWidget::item {
                margin: 6px;
                padding-top: 10px;
                padding-bottom: 6px;
                padding-left: 6px;
                padding-right: 6px;
                border-radius: 6px;
            }
            QListWidget::item:selected {
                background-color: palette(highlight);
                color: #ffffff;
                border: 1px solid palette(highlight);
            }
            QListWidget::item:hover {
                background-color: palette(alternate-base);
                border-radius: 6px;
            }
        """)
        
        self.grid_widget.itemSelectionChanged.connect(self.on_thumbnail_selected)
        grid_layout.addWidget(self.grid_widget)
        content_splitter.addWidget(grid_container)

        preview_container = QWidget()
        preview_layout = QVBoxLayout(preview_container)
        preview_layout.setContentsMargins(0, 0, 0, 0)

        self.preview_label = QLabel("Loading wallpapers...")
        self.preview_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview_label.setMinimumHeight(150)
        preview_layout.addWidget(self.preview_label)

        content_splitter.addWidget(preview_container)
        content_splitter.setSizes([450, 250])

        main_splitter.addWidget(right_widget)
        main_splitter.setSizes([280, 970])

    def populate_tree(self):
        if not os.path.exists(self.db_path):
            return

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        self.tree.clear()
        all_items_root = QTreeWidgetItem(self.tree, ["All Wallpapers"])
        self.tree.addTopLevelItem(all_items_root)

        cursor.execute("SELECT DISTINCT series FROM wallpapers WHERE series IS NOT NULL ORDER BY series")
        series_rows = cursor.fetchall()

        separate_groups = self.group_categories_checkbox.isChecked()
        self.display_to_raw_key.clear()

        for (series,) in series_rows:
            formatted_series = format_single_camel(series)
            series_item = QTreeWidgetItem(self.tree, [formatted_series])

            if separate_groups:
                cursor.execute("SELECT DISTINCT characters FROM wallpapers WHERE series = ? ORDER BY characters", (series,))
            else:
                cursor.execute("SELECT DISTINCT characters FROM wallpapers WHERE series = ? AND is_group = 0 ORDER BY characters", (series,))
            
            char_rows = cursor.fetchall()
            for (char_group_str,) in char_rows:
                for char in char_group_str.split('-'):
                    if not separate_groups:
                        formatted_char = format_character_name(char)
                        char_item = QTreeWidgetItem(series_item, [formatted_char])
                        self.display_to_raw_key[(series, formatted_char)] = char
                if separate_groups:
                    formatted_char = format_character_name(char_group_str)
                    char_item = QTreeWidgetItem(series_item, [formatted_char])
                    self.display_to_raw_key[(series, formatted_char)] = char_group_str

        conn.close()
        self.tree.collapseAll()
        all_items_root.setExpanded(True)
        all_items_root.setSelected(True)
        self.populate_grid()

    def on_search_text_changed(self, text):
        self.search_timer.start()

    def execute_search(self):
        query = self.search_bar.text().strip().lower()
        
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
            self.populate_grid()
            return

        for i in range(self.tree.topLevelItemCount()):
            top_item = self.tree.topLevelItem(i)
            if i == 0:
                top_item.setHidden(False)
                continue

            series_name = top_item.text(0).lower()
            series_matches = query in series_name

            any_char_matched = False
            for j in range(top_item.childCount()):
                char_item = top_item.child(j)
                char_name = char_item.text(0).lower()
                char_matches = query in char_name
                
                if series_matches or char_matches:
                    char_item.setHidden(False)
                    any_char_matched = True
                else:
                    char_item.setHidden(True)

            if series_matches or any_char_matched:
                top_item.setHidden(False)
                top_item.setExpanded(True)
                self.tree.expandItem(top_item)
            else:
                top_item.setHidden(True)
                self.tree.collapseItem(top_item)

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

    def get_filtered_pictures(self):
        if not os.path.exists(self.db_path):
            return []

        search_query = self.search_bar.text().strip().lower()
        selected_items = self.tree.selectedItems()
        target_series = None
        target_char = None

        if selected_items:
            item = selected_items[0]
            parent = item.parent()
            if parent is None:
                if item.text(0) != "All Wallpapers":
                    displayed_text = item.text(0)
                    conn_temp = sqlite3.connect(self.db_path)
                    cur_temp = conn_temp.cursor()
                    cur_temp.execute("SELECT DISTINCT series FROM wallpapers")
                    for (s,) in cur_temp.fetchall():
                        if format_single_camel(s) == displayed_text:
                            target_series = s
                            break
                    conn_temp.close()
            elif parent.parent() is None:
                displayed_series = parent.text(0)
                displayed_char = item.text(0)
                conn_temp = sqlite3.connect(self.db_path)
                cur_temp = conn_temp.cursor()
                cur_temp.execute("SELECT DISTINCT series FROM wallpapers")
                for (s,) in cur_temp.fetchall():
                    if format_single_camel(s) == displayed_series:
                        target_series = s
                        break
                conn_temp.close()
                target_char = self.display_to_raw_key.get((target_series, displayed_char), displayed_char)

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        query_conditions = []
        query_params = []

        show_sfw = self.sfw_checkbox.isChecked()
        show_nsfw = self.nsfw_checkbox.isChecked()

        if show_sfw and not show_nsfw:
            query_conditions.append("is_nsfw = 0")
        elif show_nsfw and not show_sfw:
            query_conditions.append("is_nsfw = 1")
        elif not show_sfw and not show_nsfw:
            query_conditions.append("1 = 0") # return nothing

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

        cursor.execute(sql, query_params)
        candidates = [row[0] for row in cursor.fetchall()]
        conn.close()

        candidates = sorted(list(set(candidates)), key=natural_sort_key)
        self.all_pictures = candidates
        return candidates

    def update_grid_layout(self):
        if not self.all_pictures:
            return

        aspect_ratio = 16 / 9
        first_pic = self.all_pictures[0]
        reader = QImageReader(first_pic)
        img_size = reader.size()
        if img_size.isValid() and img_size.height() > 0:
            aspect_ratio = img_size.width() / img_size.height()

        viewport_width = self.grid_widget.viewport().width()
        if viewport_width <= 0:
            return

        min_thumb_width = 280
        spacing = 12

        cols = max(1, viewport_width // (min_thumb_width + spacing))
        item_width = max(min_thumb_width, (viewport_width - (cols * spacing)) // cols)
        item_height = int(item_width / aspect_ratio)

        self.grid_widget.setIconSize(QSize(item_width - 16, item_height - 16))
        self.grid_widget.setGridSize(QSize(item_width, item_height + 40))

    def populate_grid(self):
        self.grid_widget.clear()
        pics = self.get_filtered_pictures()
        self.update_grid_layout()

        self._pending_pics = list(pics)
        self._load_next_chunk(is_first_chunk=True)

    def _load_next_chunk(self, is_first_chunk=False):
        if not hasattr(self, '_pending_pics') or not self._pending_pics:
            if is_first_chunk:
                self.preview_label.setText("Select a wallpaper to preview")
            return

        chunk = self._pending_pics[:200]
        self._pending_pics = self._pending_pics[200:]

        for pic in chunk:
            filename = os.path.basename(pic)
            rel_path = os.path.relpath(pic, self.wall_dir)
            target_cache_sub = os.path.join(self.cache_dir, os.path.dirname(rel_path))
            os.makedirs(target_cache_sub, exist_ok=True)
            
            thumb_path = os.path.join(target_cache_sub, filename + ".jpg")
            
            if not os.path.exists(thumb_path):
                try:
                    pixmap = QPixmap(pic)
                    thumb_pixmap = pixmap.scaled(600, 600, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
                    thumb_pixmap.save(thumb_path, "JPG", 85)
                except Exception:
                    thumb_path = pic

            item = QListWidgetItem(filename)
            item.setIcon(QIcon(thumb_path))
            item.setData(Qt.ItemDataRole.UserRole, pic)
            self.grid_widget.addItem(item)

        if is_first_chunk:
            self.preview_label.setText("Select a wallpaper to preview")

        if self._pending_pics:
            QTimer.singleShot(1, lambda: self._load_next_chunk(is_first_chunk=False))

    def select_random_wallpaper(self):
        if not self.all_pictures:
            pics = self.get_filtered_pictures()
        else:
            pics = self.all_pictures

        if not pics:
            QMessageBox.warning(self, "Warning", "No wallpapers available in the current selection!")
            return

        rand_pic = random.choice(pics)
        for i in range(self.grid_widget.count()):
            item = self.grid_widget.item(i)
            if item.data(Qt.ItemDataRole.UserRole) == rand_pic:
                self.grid_widget.setCurrentItem(item)
                self.grid_widget.scrollToItem(item)
                break

    def on_tree_item_clicked(self, item, column):
        self.populate_grid()

    def on_thumbnail_selected(self):
        selected_items = self.grid_widget.selectedItems()
        if not selected_items:
            return
        
        pic_path = selected_items[0].data(Qt.ItemDataRole.UserRole)
        self.selected_wallpaper_path = pic_path

        pixmap = QPixmap(pic_path)
        self.preview_label.setPixmap(pixmap.scaled(
            self.preview_label.size(),
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation
        ))

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.update_grid_layout()
        if self.selected_wallpaper_path:
            pixmap = QPixmap(self.selected_wallpaper_path)
            self.preview_label.setPixmap(pixmap.scaled(
                self.preview_label.size(),
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation
            ))

    def keyPressEvent(self, event):
        if event.key() == Qt.Key.Key_Escape:
            self.close()
        else:
            super().keyPressEvent(event)

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