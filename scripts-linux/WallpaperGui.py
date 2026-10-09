import os
import random
import sys
from PyQt6.QtCore import Qt, QSize, QLoggingCategory, QTimer, QThread, pyqtSignal
from PyQt6.QtGui import QPixmap, QIcon, QImageReader
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QHBoxLayout, QVBoxLayout,
    QTreeWidget, QTreeWidgetItem, QLabel, QListWidget, QListWidgetItem,
    QPushButton, QCheckBox, QSplitter, QMessageBox, QWidget, QLineEdit
)

# Suppress harmless Wayland text-input warnings
QLoggingCategory.setFilterRules("qt.qpa.wayland.textinput.warning=false")

class WallpaperScannerWorker(QThread):
    finished = pyqtSignal(dict)

    def __init__(self, wall_dir):
        super().__init__()
        self.wall_dir = wall_dir

    def run(self):
        wallpaper_cache = {}
        if not os.path.exists(self.wall_dir):
            self.finished.emit(wallpaper_cache)
            return

        for series in os.listdir(self.wall_dir):
            series_path = os.path.join(self.wall_dir, series)
            if not os.path.isdir(series_path):
                continue

            for root, dirs, files in os.walk(series_path):
                for f in files:
                    if not f.lower().endswith(('png', 'jpg', 'jpeg')):
                        continue
                    
                    full_path = os.path.join(root, f)
                    name_without_ext = os.path.splitext(f)[0]
                    clean_name = name_without_ext[5:] if name_without_ext.lower().startswith("nsfw-") else name_without_ext
                    parts = [c.strip() for c in clean_name.split('-') if c.strip()]
                    
                    characters = [c for c in parts if not c.isdigit()]
                    if not characters:
                        characters = ["General"]

                    for char_name in characters:
                        wallpaper_cache.setdefault((None, None), []).append(full_path)
                        wallpaper_cache.setdefault((series, None), []).append(full_path)
                        wallpaper_cache.setdefault((series, char_name), []).append(full_path)

        for key in wallpaper_cache:
            wallpaper_cache[key] = sorted(list(set(wallpaper_cache[key])))

        self.finished.emit(wallpaper_cache)


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
        os.makedirs(self.cache_dir, exist_ok=True)

        self.selected_wallpaper_path = None
        self.all_pictures = []
        self._updating_checkboxes = False
        self.wallpaper_cache = {}

        # Debounce timer for smooth typing
        self.search_timer = QTimer()
        self.search_timer.setSingleShot(True)
        self.search_timer.setInterval(300)
        self.search_timer.timeout.connect(self.execute_search)

        # Keyboard shortcuts for Enter / Return to apply wallpaper instantly
        from PyQt6.QtGui import QKeySequence, QShortcut
        self.enter_shortcut_1 = QShortcut(QKeySequence(Qt.Key.Key_Return), self)
        self.enter_shortcut_1.activated.connect(self.apply_wallpaper)
        self.enter_shortcut_2 = QShortcut(QKeySequence(Qt.Key.Key_Enter), self)
        self.enter_shortcut_2.activated.connect(self.apply_wallpaper)

        # 1. Build UI instantly
        self.init_ui()

        # 2. Run directory scanner in background thread so window opens immediately
        self.scanner_thread = WallpaperScannerWorker(self.wall_dir)
        self.scanner_thread.finished.connect(self.on_scanning_finished)
        self.scanner_thread.start()

    def on_scanning_finished(self, cache):
        self.wallpaper_cache = cache
        self.preview_label.setText("Loading wallpapers...")
        self.populate_tree()
        # Defer grid population so the UI renders the tree and loading state instantly first
        QTimer.singleShot(50, self.populate_grid)

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
        self.sfw_checkbox = QCheckBox("SFW")
        self.nsfw_checkbox = QCheckBox("NSFW")
        self.sfw_checkbox.setChecked(True)
        self.nsfw_checkbox.setChecked(True)
        
        self.sfw_checkbox.stateChanged.connect(self.on_sfw_toggled)
        self.nsfw_checkbox.stateChanged.connect(self.on_nsfw_toggled)
        
        toggles_layout.addWidget(self.sfw_checkbox)
        toggles_layout.addWidget(self.nsfw_checkbox)
        sidebar_layout.addLayout(toggles_layout)

        self.tree = QTreeWidget()
        self.tree.setHeaderHidden(True)
        self.tree.setAnimated(True)
        self.tree.setRootIsDecorated(True)
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
        self.tree.clear()
        all_items_root = QTreeWidgetItem(self.tree, ["All Wallpapers"])
        self.tree.addTopLevelItem(all_items_root)

        series_set = set(key[0] for key in self.wallpaper_cache.keys() if key[0] is not None)
        for series in sorted(series_set):
            series_item = QTreeWidgetItem(self.tree, [series])
            chars = set(key[1] for key in self.wallpaper_cache.keys() if key[0] == series and key[1] is not None)
            for char in sorted(chars):
                QTreeWidgetItem(series_item, [char])

        self.tree.collapseAll()
        all_items_root.setExpanded(True)
        
        # Blazing fast startup: Select the first series folder by default instead of all 11k items
        if all_items_root.childCount() > 0:
            first_series = all_items_root.child(0)
            first_series.setSelected(True)
        else:
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

    def get_filtered_pictures(self):
        search_query = self.search_bar.text().strip().lower()
        selected_items = self.tree.selectedItems()
        target_series = None
        target_char = None

        if selected_items:
            item = selected_items[0]
            parent = item.parent()
            if parent is None:
                if item.text(0) != "All Wallpapers":
                    target_series = item.text(0)
            elif parent.parent() is None:
                target_series = parent.text(0)
                target_char = item.text(0)
            else:
                target_series = parent.parent().text(0)
                target_char = parent.text(0)

        candidates = []
        if search_query and (not selected_items or selected_items[0].text(0) == "All Wallpapers"):
            for (s, c), plist in self.wallpaper_cache.items():
                if s is not None and (search_query in s.lower() or (c is not None and search_query in c.lower())):
                    candidates.extend(plist)
            candidates = sorted(list(set(candidates)))
        else:
            cache_key = (target_series, target_char)
            candidates = self.wallpaper_cache.get(cache_key, [])

            if target_series and target_char is None:
                candidates = []
                for (s, c), plist in self.wallpaper_cache.items():
                    if s == target_series:
                        candidates.extend(plist)
                candidates = sorted(list(set(candidates)))

        scope_has_sfw = any(not os.path.basename(p).lower().startswith("nsfw-") for p in candidates)
        scope_has_nsfw = any(os.path.basename(p).lower().startswith("nsfw-") for p in candidates)

        if scope_has_sfw and scope_has_nsfw:
            self.sfw_checkbox.show()
            self.nsfw_checkbox.show()
            show_sfw = self.sfw_checkbox.isChecked()
            show_nsfw = self.nsfw_checkbox.isChecked()
        else:
            self.sfw_checkbox.hide()
            self.nsfw_checkbox.hide()
            show_sfw = True
            show_nsfw = True

        pics = []
        for p in candidates:
            filename = os.path.basename(p)
            is_nsfw = filename.lower().startswith("nsfw-")
            if is_nsfw and not show_nsfw:
                continue
            if not is_nsfw and not show_sfw:
                continue
            
            if search_query:
                path_parts = p.split(os.sep)
                series_name_from_path = path_parts[-2].lower() if len(path_parts) >= 2 else ""
                filename_tokens = [t.lower() for t in filename.split('-')]
                
                matches_series = search_query in series_name_from_path
                matches_token = any(search_query in token for token in filename_tokens)
                
                if not (matches_series or matches_token):
                    continue

            pics.append(p)

        self.all_pictures = pics
        return pics

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

        # Clear the loading text instantly as soon as the first thumbnails appear
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

        # 1. Close and hide the GUI window instantly before running external scripts
        self.hide()
        self.close()
        QApplication.processEvents()

        # 2. Launch applicator detached so it doesn't block the exit pipeline
        import subprocess
        subprocess.Popen([applicator_script, rel_path])
        
        # 3. Terminate python process cleanly
        sys.exit(0)

    def keyPressEvent(self, event):
        """Allows closing/canceling the application immediately by pressing the ESC key."""
        if event.key() == Qt.Key.Key_Escape:
            self.close()
        else:
            super().keyPressEvent(event)

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = WallpaperApp()
    window.show()
    sys.exit(app.exec())