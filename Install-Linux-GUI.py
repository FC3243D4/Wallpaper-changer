#!/usr/bin/env python3
"""Install-Linux-GUI.py - graphical front-end for Install-Linux.sh.

The terminal installer stays the engine: this script only asks the questions in
a wizard and then runs the real ./Install-Linux.sh, answering its prompts the
way you chose (through the WC_ANSWER_<KEY> variables it understands, see
`./Install-Linux.sh --help`). The script runs inside a pseudo-terminal, so
anything it asks that was not anticipated (a sudo password, a surprise prompt)
shows up as a dialog instead of hanging.

If PyQt6 is missing it is installed first, with the same PkgManager.sh the
installer itself uses, and this script restarts.

    python3 Install-Linux-GUI.py                 # open the wizard
    python3 Install-Linux-GUI.py --bootstrap-only  # just make sure PyQt6 is installed
"""
import codecs
import fcntl
import html
import os
import pty
import re
import shutil
import signal
import struct
import subprocess
import sys
import termios
from pathlib import Path

REPO = Path(__file__).resolve().parent
SUPPORT = REPO / "scripts-linux" / "installSupportScripts"
INSTALLER = REPO / "Install-Linux.sh"


# --------------------------------------------------------------------------- #
# Bootstrap: PyQt6 first, using the installer's own package manager layer.
# --------------------------------------------------------------------------- #
def _notify(message: str, error: bool = True):
    """Best effort to reach a user who launched this without a terminal (file manager, launcher)."""
    print(message, file=sys.stderr if error else sys.stdout)
    for cmd in (["notify-send", "WallpaperChanger installer", message],
                ["kdialog", "--error" if error else "--msgbox", message],
                ["zenity", "--error" if error else "--info", "--text", message]):
        if shutil.which(cmd[0]) and (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
            subprocess.call(cmd, stderr=subprocess.DEVNULL)
            return


# Same PkgManager.sh the installer uses: sync the repos, install the distro's PyQt6 package.
_PKG_STEP = 'source "$1/PkgManager.sh" || exit 1; sync_repos; install_pkgs python-pyqt6'


def _install_pyqt6() -> int:
    """Returns 0 on success. Asks for privileges without needing a terminal when it can."""
    graphical = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
    # 1) polkit: the desktop's own password dialog. The package step then runs as root, so the
    #    sudo calls inside PkgManager.sh become plain calls (and cannot prompt a second time).
    if graphical and shutil.which("pkexec"):
        rc = subprocess.call(["pkexec", "bash", "-c", 'sudo() { "$@"; }; ' + _PKG_STEP, "bash", str(SUPPORT)], cwd=REPO)
        if rc == 126:                      # dialog dismissed or not authorised: respect that
            _notify("Authentication was cancelled, so PyQt6 was not installed.")
            return 126
        if rc != 127:                      # 127 = no polkit agent could ask; anything else is the real result
            return rc
        print("No polkit authentication agent is running; trying the terminal instead.")
    # 2) plain sudo, prompting on the terminal
    if sys.stdin.isatty():
        return subprocess.call(["bash", "-c", _PKG_STEP, "bash", str(SUPPORT)], cwd=REPO)
    _notify("PyQt6 has to be installed first, which needs administrator rights, and neither a polkit "
            "authentication dialog nor a terminal is available. Start this from a terminal instead.")
    return 127


def ensure_pyqt6():
    try:
        import PyQt6.QtWidgets  # noqa: F401
        return
    except ImportError:
        pass

    print("PyQt6 is not installed. Installing it first (the wallpaper picker needs it too)...")
    rc = _install_pyqt6()
    if rc in (126, 127):
        sys.exit(1)
    if rc != 0:
        _notify("Could not install PyQt6. Install your distribution's PyQt6 package and run this again.")
        sys.exit(1)

    # Restart so the freshly installed system package is picked up (also tries the
    # system python in case this one runs from a virtualenv).
    for py in (sys.executable, "/usr/bin/python3"):
        if py and os.path.exists(py) and subprocess.call(
                [py, "-c", "import PyQt6.QtWidgets"], stderr=subprocess.DEVNULL) == 0:
            os.execv(py, [py] + sys.argv)
    _notify("PyQt6 is still not importable after the package step. If the package manager reported an error, "
            "install your distribution's PyQt6 package yourself; if you use a virtualenv, run: /usr/bin/python3 " + sys.argv[0])
    sys.exit(1)


if __name__ == "__main__":
    if not INSTALLER.exists():
        sys.exit(f"Install-Linux.sh not found next to this script ({REPO}).")
    ensure_pyqt6()
    if "--bootstrap-only" in sys.argv:
        print("PyQt6 is installed.")
        sys.exit(0)

from PyQt6.QtCore import (QEventLoop, QObject, QPointF, QProcess, QProcessEnvironment, QRectF, QSize,
                          QSocketNotifier, Qt, QTimer, pyqtProperty, pyqtSignal)
from PyQt6.QtGui import QFontDatabase, QPainter, QPalette
from PyQt6.QtWidgets import (QAbstractButton, QApplication, QButtonGroup, QCheckBox, QComboBox, QFileDialog,
                             QFrame, QGridLayout, QGroupBox, QHBoxLayout, QInputDialog, QLabel, QLineEdit, QMessageBox,
                             QPlainTextEdit, QProgressBar, QProgressDialog, QPushButton, QRadioButton, QTextBrowser,
                             QVBoxLayout, QWidget, QWizard, QWizardPage)

HOME = Path.home()
CONFIG_DIR = HOME / ".config" / "WallpaperChanger"
PICTURES = HOME / "Pictures"
WALLS_DIR = PICTURES / "wallpapers"
REPO_WALLS = REPO / "wallpapers"
DEFAULT_WALLS = REPO / "wallpapersDefaultInstall" / "linux"

RULES = (
    "The wallpapers folder must look like this:\n\n"
    "  wallpapers/sfw/16-9/...     (any aspect ratios you like)\n"
    "  wallpapers/nsfw/16-9/...    (optional; same ratios as sfw)\n\n"
    "Every wallpaper needs a variant with the same file name in each ratio folder, files in nsfw/ must be\n"
    "named nsfw-<name>, and the formats must be jpg, jpeg, png, pnm, tga, tiff, webp, bmp, farbfeld or gif."
)

# Reuses the terminal installer's own functions: structure validation, ratio listing, and the
# display detection + closest-ratio matching (AspectRatioChecker.sh) behind the pre-ticked ratios.
QUERY = r'''
supportDir="$1"; src="$2"
source "$supportDir/WallpaperInstall.sh"
validate_wallpaper_structure "$src" || echo "INVALID=1"
detect_aspect_ratios "$src" ratios
printf 'RATIO=%s\n' "${ratios[@]}"
[ -d "$src/nsfw" ] && echo "NSFW=1"
tmp=$(mktemp); suggest_aspect_ratios "$src/sfw" sug > "$tmp"; sed 's/^/INFO=/' "$tmp"; rm -f "$tmp"
printf 'SUGGEST=%s\n' "${sug[@]}"
'''


def query_source(src: Path) -> dict:
    """Ask the terminal installer's helpers about a wallpapers source folder."""
    out = subprocess.run(["bash", "-c", QUERY, "bash", str(SUPPORT), str(src)], cwd=REPO,
                         capture_output=True, text=True).stdout
    info = {"invalid": False, "ratios": [], "nsfw": False, "suggested": [], "info": []}
    for line in out.splitlines():
        key, _, val = line.partition("=")
        if key == "INVALID":
            info["invalid"] = True
        elif key == "RATIO" and val:
            info["ratios"].append(val)
        elif key == "NSFW":
            info["nsfw"] = True
        elif key == "SUGGEST" and val:
            info["suggested"].append(val)
        elif key == "INFO" and val.strip():
            info["info"].append(val.rstrip())
    return info


def qt_screen_fallback(src: Path, ratios: list) -> list:
    """When neither wayland-info nor xrandr reports displays, ask Qt and map through the same checker."""
    found = []
    for scr in QApplication.screens():
        size = scr.size() * scr.devicePixelRatio()
        res = f"{int(size.width())}x{int(size.height())}"
        out = subprocess.run(["bash", str(REPO / "scripts-linux" / "AspectRatioChecker.sh"), res, str(src / "sfw")],
                             capture_output=True, text=True).stdout.strip()
        name = Path(out).name if out else ""
        if name in ratios and name not in found:
            found.append(name)
    return found


def format_detected_line(line: str) -> str:
    """Rewrite ASCII arrows and resolution 'x' into cleaner typography."""
    cleaned = re.sub(r"\s*->\s*", "  →  ", line.strip())
    cleaned = re.sub(r"\b(\d+)\s*x\s*(\d+)\b", r"\1×\2", cleaned)
    return cleaned


# --------------------------------------------------------------------------- #
# Running Install-Linux.sh in a pseudo-terminal
# --------------------------------------------------------------------------- #
class Term:
    """Just enough of a terminal for installer output: strips ANSI, honours \\r and \\b."""
    ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][A-Z0-9]|\x1b[=>78]")

    def __init__(self):
        self.cur = ""
        self.overwrite = False
        self.pending = ""
        self.dec = codecs.getincrementaldecoder("utf-8")("replace")

    def feed(self, data: bytes) -> list:
        text = self.pending + self.dec.decode(data)
        self.pending = ""
        text = self.ANSI.sub("", text)
        esc = text.rfind("\x1b")            # an escape sequence cut in half by the read: wait for the rest
        if esc != -1:
            self.pending, text = text[esc:], text[:esc]
        lines = []
        for ch in text:
            if ch == "\r":
                self.overwrite = True
            elif ch == "\n":
                lines.append(self.cur)
                self.cur, self.overwrite = "", False
            elif ch == "\b":
                self.cur = self.cur[:-1]
            else:
                if self.overwrite:
                    self.cur, self.overwrite = "", False
                self.cur += ch
        return lines


PASSWORD_RE = re.compile(r"(?i)(pass(word|phrase)|\bpin\b)[^:]*:\s*$")
PROMPT_RE = re.compile(r"[\]?:>)]\s*$")
PROGRESS_RE = re.compile(r"(\d{1,3})%|[█░]|\[[=>#. -]{5,}\]")
YESNO_RE = re.compile(r"\[[yY]/[nN]\]|\[[nN]/[yY]\]")


class PtyRunner(QObject):
    output = pyqtSignal(list, str)   # newly finished lines, the unfinished live line
    prompt = pyqtSignal(str, str)    # kind ("password" | "yesno" | "text"), prompt text
    finished = pyqtSignal(int)

    def __init__(self, argv, env, cwd, parent=None):
        super().__init__(parent)
        self.argv, self.env, self.cwd = argv, env, cwd
        self.term = Term()
        self.proc = None
        self.master = -1
        self.waiting = False
        self.idle = QTimer(self, singleShot=True, interval=800)
        self.idle.timeout.connect(self._idle)
        self.poll = QTimer(self, interval=150)
        self.poll.timeout.connect(self._check_exit)

    def start(self):
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        self.proc = subprocess.Popen(
            self.argv, stdin=slave, stdout=slave, stderr=slave, cwd=self.cwd, env=self.env,
            start_new_session=True, close_fds=True,
            preexec_fn=lambda: fcntl.ioctl(0, termios.TIOCSCTTY, 0))   # sudo & co want a controlling tty
        os.close(slave)
        os.set_blocking(self.master, False)
        self.notifier = QSocketNotifier(self.master, QSocketNotifier.Type.Read, self)
        self.notifier.activated.connect(self._readable)
        self.poll.start()

    # -- reading -------------------------------------------------------------
    def _drain(self) -> bool:
        got = False
        while True:
            try:
                data = os.read(self.master, 65536)
            except BlockingIOError:
                break
            except OSError:
                break
            if not data:
                break
            got = True
            self.waiting = False
            lines = self.term.feed(data)
            self.output.emit(lines, self.term.cur)
        return got

    def _readable(self):
        if self._drain():
            self.idle.start()

    def _check_exit(self):
        rc = self.proc.poll()
        if rc is None:
            return
        self.poll.stop()
        self.idle.stop()
        self._drain()
        self.notifier.setEnabled(False)
        if self.term.cur:
            self.output.emit([self.term.cur], "")
        os.close(self.master)
        self.finished.emit(rc)

    # -- prompts ---------------------------------------------------------------
    def _idle(self):
        live = self.term.cur
        if self.proc.poll() is not None or self.waiting or not live.strip():
            return
        if PASSWORD_RE.search(live):
            kind = "password"
        elif PROGRESS_RE.search(live):
            return                                   # a progress bar that is just quiet for a moment
        elif YESNO_RE.search(live):
            kind = "yesno"
        elif PROMPT_RE.search(live):
            kind = "text"
        else:
            return
        self.waiting = True
        self.prompt.emit(kind, live.strip())

    def reply(self, text: str, kind: str):
        self.waiting = False
        if kind == "yesno":
            # `read -n 1` takes one key and takes the terminal out of line mode while it waits; a plain
            # `read` stays in line mode and needs Enter. Ask the terminal which one is waiting.
            line_mode = bool(termios.tcgetattr(self.master)[3] & termios.ICANON)
            os.write(self.master, (text[:1] + ("\n" if line_mode else "")).encode())
        else:
            os.write(self.master, (text + "\n").encode())

    def cancel(self):
        if self.proc and self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGINT)
            except ProcessLookupError:
                return
            QTimer.singleShot(4000, self._kill)

    def _kill(self):
        if self.proc and self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def yn(flag: bool) -> str:
    return "y" if flag else "n"


# --------------------------------------------------------------------------- #
# Wizard pages
# --------------------------------------------------------------------------- #
P_START, P_EXISTING, P_SOURCE, P_OPTIONS, P_EXTRAS, P_SUMMARY, P_RUN = range(7)

ACTIONS = [
    ("install", "Install (or reinstall) WallpaperChanger", "Dependencies, scripts, wallpapers, themes.", None),
    ("update_scripts", "Update the installed scripts", "Copies only new and changed scripts.", "--update-scripts"),
    ("update_wallpapers", "Sync wallpapers from the repo", "Copies only new and updated wallpapers.", "--update-wallpapers"),
    ("thumbnails", "Install the thumbnail watcher", "Keeps the picker's thumbnails up to date automatically.", "--thumbnails"),
    ("zen", "Set up Zen Browser live theme reload", "Needs sudo and a download.", "--zen-hotreload"),
]


def label(text, wrap=True, bold=False, point_delta=0, align=None):
    lab = QLabel(text)
    lab.setWordWrap(wrap)
    f = lab.font()
    if bold:
        f.setBold(True)
    if point_delta:
        sz = f.pointSizeF()
        if sz > 0:
            f.setPointSizeF(sz + point_delta)
    if bold or point_delta:
        lab.setFont(f)
    if align is not None:
        lab.setAlignment(align)
    return lab


class SwitchToggle(QAbstractButton):
    """Pill switch using native palette colors."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setCheckable(True)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self._thumb_pos = 0.0
        self.toggled.connect(self._on_toggled)

    @pyqtProperty(float)
    def thumbPos(self) -> float:
        return self._thumb_pos

    @thumbPos.setter
    def thumbPos(self, val: float):
        self._thumb_pos = val
        self.update()

    def _on_toggled(self, checked: bool):
        self._thumb_pos = 1.0 if checked else 0.0
        self.update()

    def sizeHint(self) -> QSize:
        return QSize(46, 24)

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        pal = self.palette()

        w, h = float(self.width()), float(self.height())
        pill_h = min(h - 2.0, 24.0)
        pill_w = max(w - 2.0, pill_h * 1.8)
        x0 = (w - pill_w) / 2.0
        y0 = (h - pill_h) / 2.0
        radius = pill_h / 2.0

        track_color = pal.color(QPalette.ColorRole.Highlight) if self.isChecked() else pal.color(QPalette.ColorRole.Midlight)
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(track_color)
        p.drawRoundedRect(QRectF(x0, y0, pill_w, pill_h), radius, radius)

        margin = 3.0
        thumb_d = pill_h - margin * 2.0
        min_x = x0 + margin
        max_x = x0 + pill_w - margin - thumb_d
        tx = min_x + (max_x - min_x) * self._thumb_pos
        ty = y0 + margin

        thumb_color = pal.color(QPalette.ColorRole.HighlightedText) if self.isChecked() else pal.color(QPalette.ColorRole.Base)
        p.setBrush(thumb_color)
        p.drawEllipse(QRectF(tx, ty, thumb_d, thumb_d))


class ActionCard(QFrame):
    """Selectable option card using native system palette roles."""

    def __init__(self, radio: QRadioButton, title: str, desc: str, parent=None):
        super().__init__(parent)
        self.radio = radio
        self.setObjectName("ActionCard")
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setCursor(Qt.CursorShape.PointingHandCursor)

        lay = QHBoxLayout(self)
        lay.setContentsMargins(14, 10, 14, 10)
        lay.setSpacing(12)

        radio.setText("")
        lay.addWidget(radio, 0, Qt.AlignmentFlag.AlignTop)

        text_col = QVBoxLayout()
        text_col.setSpacing(2)
        self.title_lbl = label(title, bold=True)
        self.desc_lbl = label(desc)
        text_col.addWidget(self.title_lbl)
        text_col.addWidget(self.desc_lbl)
        lay.addLayout(text_col, 1)

        radio.toggled.connect(self._sync_state)
        self._sync_state(radio.isChecked())

    def _sync_state(self, checked: bool):
        self.setProperty("selected", checked and self.isEnabled())
        self.style().unpolish(self)
        self.style().polish(self)

    def setEnabled(self, enabled: bool):
        super().setEnabled(enabled)
        self.radio.setEnabled(enabled)
        self.setCursor(Qt.CursorShape.PointingHandCursor if enabled else Qt.CursorShape.ArrowCursor)
        self._sync_state(self.radio.isChecked())

    def mousePressEvent(self, event):
        if self.isEnabled() and event.button() == Qt.MouseButton.LeftButton:
            self.radio.setChecked(True)
        super().mousePressEvent(event)


class RatioTile(QFrame):
    """Selectable tile for an aspect ratio inside a responsive multi-column grid."""

    def __init__(self, ratio: str, is_suggested: bool, parent=None):
        super().__init__(parent)
        self.ratio = ratio
        self.setObjectName("RatioTile")
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setMinimumWidth(165)

        lay = QHBoxLayout(self)
        lay.setContentsMargins(12, 10, 12, 10)
        lay.setSpacing(10)

        self.checkbox = QCheckBox()
        self.checkbox.setChecked(is_suggested)
        lay.addWidget(self.checkbox, 0, Qt.AlignmentFlag.AlignVCenter)

        col = QVBoxLayout()
        col.setSpacing(2)
        col.addWidget(label(ratio, wrap=False, bold=True, point_delta=1))
        if is_suggested:
            col.addWidget(label("Connected display", wrap=False, point_delta=-1))
        lay.addLayout(col, 1)

        self.checkbox.toggled.connect(self._sync_state)
        self._sync_state(is_suggested)

    def isChecked(self) -> bool:
        return self.checkbox.isChecked()

    def setChecked(self, checked: bool):
        self.checkbox.setChecked(checked)

    def _sync_state(self, checked: bool):
        self.setProperty("selected", checked)
        self.style().unpolish(self)
        self.style().polish(self)

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self.checkbox.toggle()
        super().mousePressEvent(event)


class RatioGrid(QWidget):
    """Responsive grid that reflows aspect-ratio tiles across columns & rows on resize."""

    def __init__(self, tiles: list[RatioTile], parent=None):
        super().__init__(parent)
        self.tiles = tiles
        self._cols = 0
        self.grid = QGridLayout(self)
        self.grid.setContentsMargins(0, 0, 0, 0)
        self.grid.setSpacing(10)
        self._relayout(force=True)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._relayout()

    def _relayout(self, force: bool = False):
        if not self.tiles:
            return
        avail = max(self.width(), 1)
        min_tile_w = 185
        cols = max(1, min(len(self.tiles), avail // min_tile_w))
        if cols == self._cols and not force:
            return
        self._cols = cols

        while self.grid.count():
            self.grid.takeAt(0)

        for idx, tile in enumerate(self.tiles):
            r, c = divmod(idx, cols)
            self.grid.addWidget(tile, r, c)

        for c in range(cols):
            self.grid.setColumnStretch(c, 1)


class StartPage(QWizardPage):
    def __init__(self):
        super().__init__()
        self.setTitle("WallpaperChanger")
        self.setSubTitle("What would you like to do?")
        lay = QVBoxLayout(self)
        lay.setSpacing(8)

        self.banner = QFrame()
        self.banner.setObjectName("StatusBanner")
        self.banner.setFrameShape(QFrame.Shape.StyledPanel)
        banner_lay = QHBoxLayout(self.banner)
        banner_lay.setContentsMargins(12, 8, 12, 8)
        self.note = label("")
        banner_lay.addWidget(self.note)
        lay.addWidget(self.banner)

        self.group = QButtonGroup(self)
        self.radios = {}
        self.cards = {}
        for i, (key, title, desc, _flag) in enumerate(ACTIONS):
            rb = QRadioButton()
            rb.setToolTip(desc)
            self.group.addButton(rb, i)
            self.radios[key] = rb
            card = ActionCard(rb, title, desc)
            self.cards[key] = card
            lay.addWidget(card)

        self.radios["install"].setChecked(True)
        lay.addStretch()
        self.initializePage()

    def initializePage(self):
        """Which maintenance actions make sense depends on what is installed right now."""
        installed = CONFIG_DIR.is_dir()
        for key in ("update_scripts", "thumbnails"):
            self.cards[key].setEnabled(installed)
        self.cards["update_wallpapers"].setEnabled(WALLS_DIR.is_dir())
        if not self.group.checkedButton().isEnabled():
            self.radios["install"].setChecked(True)
        self.note.setText("WallpaperChanger is already installed on this system." if installed else "")
        self.banner.setVisible(installed)

    def action(self):
        return ACTIONS[self.group.checkedId()][0]

    def nextId(self):
        if self.action() != "install":
            return P_RUN
        if self.wizard().needs_existing_page():
            return P_EXISTING
        return P_OPTIONS if self.wizard().has_repo_wallpapers() else P_SOURCE


class ExistingPage(QWizardPage):
    def __init__(self):
        super().__init__()
        self.setTitle("Existing files found")
        self.setSubTitle("Choose what happens to what is already on this system. Nothing is deleted unless you say so.")
        lay = QVBoxLayout(self)
        lay.setSpacing(14)

        split_row = QHBoxLayout()
        split_row.setSpacing(14)

        self.cfg_combo = self.wall_combo = None
        if CONFIG_DIR.is_dir():
            box = QGroupBox("Scripts")
            v = QVBoxLayout(box)
            v.setContentsMargins(12, 14, 12, 14)
            self.cfg_combo = QComboBox()
            self.cfg_combo.addItems([
                "Update scripts and keep settings",
                "Delete and install clean",
                "Leave untouched",
            ])
            v.addWidget(self.cfg_combo)
            v.addStretch()
            split_row.addWidget(box, 1)

        if WALLS_DIR.is_dir():
            box = QGroupBox("Wallpapers")
            v = QVBoxLayout(box)
            v.setContentsMargins(12, 14, 12, 14)
            self.wall_combo = QComboBox()
            self.wall_combo.addItems([
                "Keep existing and add/update from source",
                "Keep existing and copy nothing",
                "Delete everything first, then copy",
            ])
            v.addWidget(self.wall_combo)
            v.addStretch()
            split_row.addWidget(box, 1)

        if split_row.count():
            lay.addLayout(split_row)

        self.make_pictures = None
        if not PICTURES.is_dir():
            self.make_pictures = QCheckBox(f"Create {PICTURES} (it does not exist)")
            self.make_pictures.setChecked(True)
            lay.addWidget(self.make_pictures)
        lay.addStretch()

    def nextId(self):
        return P_OPTIONS if self.wizard().has_repo_wallpapers() else P_SOURCE

    def answers(self) -> dict:
        a = {}
        if self.cfg_combo:
            c = self.cfg_combo.currentIndex()
            a["DELETE_CONFIG_DIR"] = yn(c == 1)
            a["COPY_SCRIPTS"] = yn(c == 0)
        if self.wall_combo:
            w = self.wall_combo.currentIndex()
            a["DELETE_WALLPAPERS_DIR"] = yn(w == 2)
            a["COPY_WALLPAPERS"] = yn(w in (0, 2))
        if self.make_pictures:
            a["CREATE_PICTURES_DIR"] = yn(self.make_pictures.isChecked())
            a["COPY_WALLPAPERS"] = yn(self.make_pictures.isChecked())
        return a

    def describe(self) -> list:
        out = []
        if self.cfg_combo:
            out.append(["- Scripts: updated, settings kept",
                        "- Scripts: REMOVED, then installed clean",
                        "- Scripts: left untouched"][self.cfg_combo.currentIndex()])
        if self.wall_combo:
            out.append(["- Wallpapers: kept, new ones added",
                        "- Wallpapers: kept, nothing copied",
                        "- Wallpapers: EVERYTHING DELETED first"][self.wall_combo.currentIndex()])
        if self.make_pictures and self.make_pictures.isChecked():
            out.append(f"- {PICTURES} will be created")
        return out


class SourcePage(QWizardPage):
    def __init__(self):
        super().__init__()
        self.setTitle("Wallpapers")
        self.setSubTitle("Where should the wallpapers come from?")
        self.lay = QVBoxLayout(self)
        self.group = QButtonGroup(self)
        self.folder = QLineEdit()
        self.folder.setPlaceholderText("Folder containing sfw/ (and optionally nsfw/)")
        browse = QPushButton("Browse...")
        browse.clicked.connect(self._browse)
        self.url = QLineEdit()
        self.url.setPlaceholderText("https://github.com/user/wallpapers.git")
        self.created = False

        for i, text in enumerate(["Use the bundled default wallpapers",
                                  "Use my own folder", "Clone a git repository of wallpapers"]):
            rb = QRadioButton(text)
            self.group.addButton(rb, i)
            self.lay.addWidget(rb)
            if i == 1:
                row = QHBoxLayout()
                row.addWidget(self.folder)
                row.addWidget(browse)
                self.lay.addLayout(row)
            if i == 2:
                self.lay.addWidget(self.url)
        self.group.button(0).setChecked(True)
        self.lay.addWidget(label(RULES))
        self.lay.addStretch()

    def _browse(self):
        d = QFileDialog.getExistingDirectory(self, "Wallpapers folder", str(HOME))
        if d:
            self.folder.setText(d)
            self.group.button(1).setChecked(True)

    def source_dir(self) -> Path:
        return REPO_WALLS if (REPO_WALLS.exists() or REPO_WALLS.is_symlink()) else DEFAULT_WALLS

    def validatePage(self) -> bool:
        if self.created:                                    # user came back and may have chosen differently
            self._undo()
            self.created = False
        choice = self.group.checkedId()
        if choice == 0:
            return True
        created = False
        try:
            if choice == 1:
                src = Path(self.folder.text().strip()).expanduser()
                if not src.is_dir():
                    return self._fail("Pick an existing folder.")
                os.symlink(src.resolve(), REPO_WALLS)
                created = True
            else:
                url = self.url.text().strip()
                if not url:
                    return self._fail("Paste the repository link.")
                if not shutil.which("git"):
                    return self._fail("git is not installed.")
                ok, msg = self._clone(url)
                if not ok:
                    return self._fail("Cloning failed:\n" + msg)
                created = True
            if query_source(REPO_WALLS)["invalid"]:
                self._undo()
                return self._fail("That folder does not have a valid structure.\n\n" + RULES)
            self.created = True
            return True
        except OSError as e:
            if created:
                self._undo()
            return self._fail(str(e))

    def _undo(self):
        if REPO_WALLS.is_symlink():
            REPO_WALLS.unlink()
        elif REPO_WALLS.is_dir():
            shutil.rmtree(REPO_WALLS, ignore_errors=True)   # only ever the clone this page just made

    def _fail(self, text) -> bool:
        QMessageBox.warning(self, "Wallpapers", text)
        return False

    def _clone(self, url):
        dlg = QProgressDialog("Cloning the repository...", "Cancel", 0, 0, self)
        dlg.setWindowModality(Qt.WindowModality.WindowModal)
        dlg.setMinimumDuration(0)
        proc = QProcess(self)
        env = QProcessEnvironment.systemEnvironment()
        env.insert("GIT_TERMINAL_PROMPT", "0")              # fail instead of waiting for a login on a terminal
        proc.setProcessEnvironment(env)
        proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        loop = QEventLoop()
        proc.finished.connect(loop.quit)
        proc.errorOccurred.connect(loop.quit)
        dlg.canceled.connect(proc.kill)
        proc.start("git", ["clone", "--depth", "1", url, str(REPO_WALLS)])
        dlg.show()
        loop.exec()
        dlg.close()
        ok = proc.exitStatus() == QProcess.ExitStatus.NormalExit and proc.exitCode() == 0
        if not ok:
            self._undo()
        return ok, bytes(proc.readAllStandardOutput()).decode(errors="replace")[-600:]


class OptionsPage(QWizardPage):
    def __init__(self):
        super().__init__()
        self.setTitle("Aspect ratios & wallpapers")
        self.lay = QVBoxLayout(self)
        self.lay.setSpacing(14)
        self.tiles = []
        self.nsfw_switch = SwitchToggle()

    def _clear_layout(self, layout):
        while layout.count():
            item = layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
            elif item.layout():
                self._clear_layout(item.layout())

    def initializePage(self):
        self._clear_layout(self.lay)
        self.tiles = []

        src = self.wizard().page(P_SOURCE).source_dir()
        q = query_source(src)
        if q["invalid"]:                                       # same fallback the installer applies
            src = DEFAULT_WALLS
            q = query_source(src)
        self.q = q
        self.setSubTitle("Review detected displays, select aspect ratios, and choose wallpaper sets.")

        suggested = q["suggested"] or qt_screen_fallback(src, q["ratios"])
        display_lines = [
            format_detected_line(ln)
            for ln in q["info"]
            if ln.strip() and not ln.strip().lower().startswith("connected displays")
        ]
        if not display_lines and suggested:
            display_lines = [f"Matched ratio  →  {r}" for r in suggested]

        if display_lines:
            detected_box = QFrame()
            detected_box.setObjectName("DetectedBox")
            detected_box.setFrameShape(QFrame.Shape.StyledPanel)
            d_lay = QVBoxLayout(detected_box)
            d_lay.setContentsMargins(20, 12, 20, 12)
            d_lay.setSpacing(6)
            d_lay.addWidget(label("Detected displays", bold=True, point_delta=1, align=Qt.AlignmentFlag.AlignCenter))
            for d_line in display_lines:
                d_lay.addWidget(label(d_line, bold=True, point_delta=2, align=Qt.AlignmentFlag.AlignCenter))

            center_row = QHBoxLayout()
            center_row.addStretch()
            center_row.addWidget(detected_box)
            center_row.addStretch()
            self.lay.addLayout(center_row)

        self.lay.addWidget(label("Aspect ratios to install", bold=True))

        if len(q["ratios"]) > 1:
            for r in q["ratios"]:
                is_sug = (r in suggested) if suggested else True
                self.tiles.append(RatioTile(r, is_sug))
            self.lay.addWidget(RatioGrid(self.tiles))
        else:
            only = q["ratios"][0] if q["ratios"] else "-"
            self.lay.addWidget(label(f"Only {only} is available in this wallpaper source."))

        self.nsfw_switch = SwitchToggle()
        self.nsfw_switch.setChecked(False)
        nsfw_lbl = label("NSFW wallpapers", bold=True)
        nsfw_lbl.setCursor(Qt.CursorShape.PointingHandCursor)
        nsfw_lbl.mousePressEvent = lambda _e: self.nsfw_switch.toggle()

        if q["nsfw"]:
            row = QHBoxLayout()
            row.addStretch()
            row.addWidget(self.nsfw_switch, 0, Qt.AlignmentFlag.AlignVCenter)
            row.addSpacing(10)
            row.addWidget(nsfw_lbl, 0, Qt.AlignmentFlag.AlignVCenter)
            row.addStretch()
            self.lay.addLayout(row)

        self.lay.addStretch()

    def nextId(self):
        return P_EXTRAS

    def chosen_ratios(self):
        return [t.ratio for t in self.tiles if t.isChecked()]

    def validatePage(self):
        if self.tiles and not self.chosen_ratios():
            QMessageBox.information(self, "Aspect ratios", "Select at least one aspect ratio.")
            return False
        return True

    def answers(self) -> dict:
        a = {"NSFW": yn(self.nsfw_switch.isChecked())}
        if self.tiles:
            a["RATIOS"] = " ".join(self.chosen_ratios())
        return a


class ExtrasPage(QWizardPage):
    def __init__(self):
        super().__init__()
        self.setTitle("Extras")
        self.setSubTitle("Optional browser integration and applying a wallpaper right away.")
        lay = QVBoxLayout(self)
        lay.setSpacing(12)

        box = QGroupBox("Post-install & browser options")
        v = QVBoxLayout(box)
        v.setSpacing(8)
        self.zen = QCheckBox("Set up Zen Browser live theme reload if Zen is found (needs sudo and a download)")
        self.apply = QCheckBox("Apply a random wallpaper when finished (programs may close and reopen to take the theme)")
        self.apply.setChecked(True)
        v.addWidget(self.zen)
        v.addWidget(self.apply)
        lay.addWidget(box)
        lay.addStretch()

    def nextId(self):
        return P_SUMMARY

    def answers(self) -> dict:
        return {"APPLY_NOW": yn(self.apply.isChecked())}


class SummaryPage(QWizardPage):
    def __init__(self):
        super().__init__()
        self.setTitle("Ready to install")
        self.setCommitPage(True)
        lay = QVBoxLayout(self)
        self.text = QLabel()
        self.text.setWordWrap(True)
        self.text.setTextFormat(Qt.TextFormat.PlainText)
        lay.addWidget(self.text)
        lay.addStretch()

    def initializePage(self):
        w = self.wizard()
        o = w.page(P_OPTIONS)
        e = w.page(P_EXTRAS)
        lines = list(w.page(P_EXISTING).describe())
        src = w.page(P_SOURCE).source_dir()
        lines.append(f"- Wallpapers from: {src}")
        if o.tiles:
            lines.append("- Aspect ratios: " + ", ".join(o.chosen_ratios()))
        if o.nsfw_switch.isChecked():
            lines.append("- NSFW wallpapers included")
        if e.zen.isChecked():
            lines.append("- Zen live theme reload (if Zen is found)")
        lines.append("- A random wallpaper is applied at the end" if e.apply.isChecked() else "- No wallpaper is applied at the end")
        self.text.setText("This will run the installer with these choices:\n\n" + "\n".join(lines) +
                          "\n\nMissing packages are installed with your package manager; a dialog will ask for your "
                          "password when it is needed.")
        w.setButtonText(QWizard.WizardButton.CommitButton, "Install")


def _cmd_block(cmd: str) -> str:
    return (
        f"<pre style='background: palette(window); border: 1px solid palette(midlight); "
        f"border-radius: 6px; padding: 8px 10px; margin: 4px 0 12px 0; white-space: pre-wrap;'>"
        f"{html.escape(cmd)}</pre>"
    )


def build_completion_html(action: str, rc: int, env: dict, log_lines: list[str]) -> str:
    """Build a formatted summary inside the GUI using native text/code blocks."""
    cfg = str(CONFIG_DIR)
    walls = str(WALLS_DIR)
    cache = str(HOME / ".cache" / "wallpaper_ratios.cache")
    repo_str = html.escape(str(REPO))

    if rc != 0:
        tail = "\n".join(log_lines[-15:]).strip()
        tail_html = _cmd_block(tail) if tail else ""
        return (
            f"<h3 style='margin: 0 0 6px 0;'>Action stopped (exit code {rc})</h3>"
            f"<p style='margin: 0 0 10px 0;'>The process did not finish cleanly. Click <b>Show log</b> above to inspect the full output.</p>"
            f"{tail_html}"
        )

    if action == "update_scripts":
        return (
            f"<h3 style='margin: 0 0 6px 0;'>Scripts updated</h3>"
            f"<p style='margin: 0 0 10px 0;'>New and changed scripts were copied to <code>{html.escape(cfg)}</code>.</p>"
            f"<p style='margin: 0 0 4px 0;'><b>Open the wallpaper menu</b></p>"
            f"{_cmd_block(f'{cfg}/WallpaperMenu.sh')}"
            f"<p style='margin: 0;'>If you added or removed wallpapers recently, delete <code>{html.escape(cache)}</code> so ratios refresh.</p>"
        )

    if action == "update_wallpapers":
        return (
            f"<h3 style='margin: 0 0 6px 0;'>Wallpapers synced</h3>"
            f"<p style='margin: 0 0 10px 0;'>Matching aspect ratio folders in <code>{html.escape(walls)}</code> were synced and the ratio cache was cleared.</p>"
            f"<p style='margin: 0 0 4px 0;'><b>Open the wallpaper menu</b></p>"
            f"{_cmd_block(f'{cfg}/WallpaperMenu.sh')}"
        )

    if action == "thumbnails":
        return (
            f"<h3 style='margin: 0 0 6px 0;'>Thumbnail watcher installed</h3>"
            f"<p style='margin: 0;'><code>wallpaper-thumbnails.path</code> is enabled and will generate thumbnails automatically when wallpapers change.</p>"
        )

    if action == "zen":
        return (
            f"<h3 style='margin: 0 0 6px 0;'>Zen Browser live theme reload configured</h3>"
            f"<p style='margin: 0;'>Zen Browser will automatically reload theme updates when wallpapers are applied.</p>"
        )

    nsfw_on = env.get("WC_ANSWER_NSFW") == "y"
    use_xrandr = any("Updating Xrandr scripts" in ln for ln in log_lines)
    custom_walls = any("No ./wallpapers folder found" not in ln for ln in log_lines) and (REPO_WALLS.exists() or REPO_WALLS.is_symlink())

    if use_xrandr:
        menu_cmd = f"{cfg}/WallpaperMenuXrandr.sh"
        random_cmd = f"{cfg}/WallpaperApplicatorXrandr.sh random"
        auto_cmd = f"{cfg}/WallpaperRandomAutoXrandr.sh"
        sfw_cmd = f"{cfg}/WallpaperApplicatorXrandr.sh random sfw"
        nsfw_cmd = f"{cfg}/WallpaperApplicatorXrandr.sh random nsfw"
        auto_sfw = f"{cfg}/WallpaperRandomAutoXrandr.sh sfw"
        auto_nsfw = f"{cfg}/WallpaperRandomAutoXrandr.sh nsfw"
    else:
        menu_cmd = f"{cfg}/WallpaperMenu.sh"
        random_cmd = f"{cfg}/WallpaperApplication.sh random"
        auto_cmd = f"{cfg}/WallpaperRandomAuto.sh"
        sfw_cmd = f"{cfg}/WallpaperApplicator.sh random sfw"
        nsfw_cmd = f"{cfg}/WallpaperApplicator.sh random nsfw"
        auto_sfw = f"{cfg}/WallpaperRandomAuto.sh sfw"
        auto_nsfw = f"{cfg}/WallpaperRandomAuto.sh nsfw"

    parts = [
        "<h3 style='margin: 0 0 6px 0;'>Installation complete!</h3>",
        "<p style='margin: 0 0 12px 0;'>Wallpapers are applied across connected displays at their matching aspect ratio, and dominant colors are sent to supported OpenRGB devices automatically.</p>",
        "<p style='margin: 0 0 4px 0;'><b>Open the wallpaper menu</b></p>",
        _cmd_block(menu_cmd),
        "<p style='margin: 0 0 4px 0;'><b>Apply a random wallpaper or start auto-rotation (every 30 minutes)</b></p>",
        _cmd_block(f"{random_cmd}\n{auto_cmd}"),
    ]

    if nsfw_on:
        parts.extend([
            "<p style='margin: 0 0 4px 0;'><b>SFW and NSFW commands</b></p>",
            _cmd_block(f"{sfw_cmd}\n{nsfw_cmd}\n{auto_sfw}\n{auto_nsfw}"),
        ])

    if not custom_walls:
        parts.append(
            f"<p style='margin: 0 0 10px 0;'><b>Adding wallpapers:</b> Place images into aspect-ratio folders (such as <code>16-9</code>, <code>21-9</code>) under <code>{html.escape(walls)}</code>.</p>"
        )

    parts.extend([
        "<p style='margin: 0 0 4px 0;'><b>Thumbnail watcher & future updates</b></p>",
        _cmd_block(
            f"cd {repo_str} && ./Install-Linux.sh --thumbnails\n"
            f"cd {repo_str} && ./Install-Linux.sh --update-scripts\n"
            f"cd {repo_str} && ./Install-Linux.sh --update-wallpapers"
        ),
        f"<p style='margin: 0;'>The first run builds an aspect ratio cache; if you add or remove wallpapers later, delete <code>{html.escape(cache)}</code> so changes are picked up.</p>",
    ])
    return "".join(parts)


class RunPage(QWizardPage):
    def __init__(self):
        super().__init__()
        self.setTitle("Working")
        self.done = False
        self.runner = None
        self._log_lines = []
        self._run_env = {}
        self._run_action = "install"

        lay = QVBoxLayout(self)
        lay.setSpacing(8)

        header = QHBoxLayout()
        self.status = label("Starting...", bold=True)
        self.toggle_log_btn = QPushButton("Show log")
        self.toggle_log_btn.setCheckable(True)
        self.toggle_log_btn.setVisible(False)
        self.toggle_log_btn.toggled.connect(self._on_toggle_log)
        header.addWidget(self.status, 1)
        header.addWidget(self.toggle_log_btn)
        lay.addLayout(header)

        self.bar = QProgressBar()
        self.bar.setRange(0, 0)
        lay.addWidget(self.bar)

        self.summary_card = QTextBrowser()
        self.summary_card.setObjectName("CompletionCard")
        self.summary_card.setOpenExternalLinks(False)
        self.summary_card.setVisible(False)
        lay.addWidget(self.summary_card, 1)

        mono = QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont)
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setFont(mono)
        self.log.setMaximumBlockCount(5000)
        lay.addWidget(self.log, 1)

        self.liveline = QLabel()                    # the line still being written: progress bars, prompts
        self.liveline.setFont(mono)
        self.liveline.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        lay.addWidget(self.liveline)

    def _on_toggle_log(self, checked: bool):
        self.log.setVisible(checked)
        self.summary_card.setVisible(not checked)
        self.toggle_log_btn.setText("Hide log" if checked else "Show log")

    def isComplete(self):
        return self.done

    def initializePage(self):
        w = self.wizard()
        self.setSubTitle(w.run_title())
        self.done = False
        self._log_lines = []
        self._run_action = w.action()
        self._run_env = w.run_env()

        self.log.clear()
        self.log.setVisible(True)
        self.summary_card.clear()
        self.summary_card.setVisible(False)
        self.toggle_log_btn.setChecked(False)
        self.toggle_log_btn.setVisible(False)
        self.liveline.clear()
        self.bar.setRange(0, 0)
        self.status.setText("Starting...")

        env = dict(os.environ, TERM="xterm-256color", **self._run_env)
        self.runner = PtyRunner(["bash", str(INSTALLER), *w.run_args()], env, str(REPO), self)
        self.runner.output.connect(self._output)
        self.runner.prompt.connect(self._prompt)
        self.runner.finished.connect(self._finished)
        self.runner.start()

    def _output(self, lines, live):
        for ln in lines:
            self._log_lines.append(ln)
            self.log.appendPlainText(ln)
        self.liveline.setText(live)
        m = re.search(r"(\d{1,3})%", live)
        if m:
            self.bar.setRange(0, 100)
            self.bar.setValue(min(100, int(m.group(1))))
        elif lines:
            self.bar.setRange(0, 0)                 # a new step started: back to "busy"
        text = (lines[-1] if lines else live).strip()
        if text and not re.search(r"[█░]", text):
            self.status.setText(text[:110])

    def _prompt(self, kind, text):
        if kind == "password":
            pw, ok = QInputDialog.getText(self, "Password needed", text, QLineEdit.EchoMode.Password)
            if not ok:
                self.runner.cancel()
                return
            self.runner.reply(pw, "password")
        elif kind == "yesno":
            default_yes = bool(re.search(r"\[Y/n\]", text))
            btns = QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            r = QMessageBox.question(self, "The installer asks", text, btns,
                                     QMessageBox.StandardButton.Yes if default_yes else QMessageBox.StandardButton.No)
            self.runner.reply("y" if r == QMessageBox.StandardButton.Yes else "n", "yesno")
        else:
            ans, ok = QInputDialog.getText(self, "The installer asks", text)
            if not ok:
                self.runner.cancel()
                return
            self.runner.reply(ans, "text")

    def _finished(self, rc):
        self.done = True
        self.bar.setRange(0, 100)
        self.bar.setValue(100 if rc == 0 else self.bar.value())
        self.liveline.clear()

        if rc == 0:
            self.status.setText("Done.")
            self.setTitle("Finished")
        else:
            self.status.setText(f"The installer stopped with exit code {rc} - see the log above.")
            self.setTitle("Something went wrong")

        self.summary_card.setHtml(build_completion_html(self._run_action, rc, self._run_env, self._log_lines))
        self.summary_card.setVisible(True)
        self.log.setVisible(False)
        self.toggle_log_btn.setVisible(True)
        self.toggle_log_btn.setText("Show log")

        w = self.wizard()
        w.button(QWizard.WizardButton.CancelButton).setEnabled(False)
        self.completeChanged.emit()


PALETTE_STYLESHEET = """
QFrame#StatusBanner, QFrame#DetectedBox {
    border: 1px solid palette(midlight);
    border-radius: 8px;
    background: palette(base);
    color: palette(windowText);
}
QFrame#ActionCard, QFrame#RatioTile {
    border: 1px solid palette(midlight);
    border-radius: 8px;
    background: palette(base);
    color: palette(windowText);
}
QFrame#ActionCard:hover:!disabled, QFrame#RatioTile:hover {
    border: 1px solid palette(highlight);
}
QFrame#ActionCard[selected="true"], QFrame#RatioTile[selected="true"] {
    border: 2px solid palette(highlight);
}
QTextBrowser#CompletionCard {
    border: 1px solid palette(midlight);
    border-radius: 8px;
    background: palette(base);
    color: palette(text);
    padding: 12px;
}
"""


class InstallerWizard(QWizard):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("WallpaperChanger installer")
        self.setWizardStyle(QWizard.WizardStyle.ModernStyle)
        self.setOption(QWizard.WizardOption.NoBackButtonOnLastPage, True)
        self.setStyleSheet(PALETTE_STYLESHEET)
        self.resize(780, 600)
        self.setPage(P_START, StartPage())
        self.setPage(P_EXISTING, ExistingPage())
        self.setPage(P_SOURCE, SourcePage())
        self.setPage(P_OPTIONS, OptionsPage())
        self.setPage(P_EXTRAS, ExtrasPage())
        self.setPage(P_SUMMARY, SummaryPage())
        self.setPage(P_RUN, RunPage())

    def has_repo_wallpapers(self):
        return REPO_WALLS.exists() or REPO_WALLS.is_symlink()

    def needs_existing_page(self):
        return CONFIG_DIR.is_dir() or WALLS_DIR.is_dir() or not PICTURES.is_dir()

    def action(self):
        return self.page(P_START).action()

    def run_title(self):
        return next(t for k, t, _d, _f in ACTIONS if k == self.action())

    def run_args(self):
        return [next(f for k, _t, _d, f in ACTIONS if k == self.action()) or "--install"]

    def run_env(self) -> dict:
        if self.action() != "install":
            return {}
        a = {"CLONE_OFFER": "n"}
        a.update(self.page(P_EXISTING).answers() if self.needs_existing_page() else {})
        a.update(self.page(P_OPTIONS).answers())
        a.update(self.page(P_EXTRAS).answers())
        env = {f"WC_ANSWER_{k}": v for k, v in a.items()}
        env["ZEN_HOTRELOAD_AUTO"] = "yes" if self.page(P_EXTRAS).zen.isChecked() else "no"
        return env

    def reject(self):
        r = self.page(P_RUN).runner
        if r and r.proc and r.proc.poll() is None:
            if QMessageBox.question(self, "Cancel", "Stop the installation?") != QMessageBox.StandardButton.Yes:
                return
            r.cancel()
        super().reject()


def main():
    app = QApplication(sys.argv)
    wiz = InstallerWizard()
    wiz.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())