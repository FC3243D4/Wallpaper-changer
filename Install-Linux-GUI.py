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
def ensure_pyqt6():
    try:
        import PyQt6.QtWidgets  # noqa: F401
        return
    except ImportError:
        pass

    print("PyQt6 is not installed. Installing it first (the wallpaper picker needs it too)...")
    if not sys.stdin.isatty():
        sys.exit("Package installation needs your sudo password: run this script from a terminal.")
    snippet = 'source "$1/PkgManager.sh" || exit 1; sync_repos; install_pkgs python-pyqt6'
    if subprocess.call(["bash", "-c", snippet, "bash", str(SUPPORT)], cwd=REPO) != 0:
        sys.exit("Could not install PyQt6. Install your distribution's PyQt6 package and run this again.")

    # Restart so the freshly installed system package is picked up (also tries the
    # system python in case this one runs from a virtualenv).
    for py in (sys.executable, "/usr/bin/python3"):
        if py and os.path.exists(py) and subprocess.call(
                [py, "-c", "import PyQt6.QtWidgets"], stderr=subprocess.DEVNULL) == 0:
            os.execv(py, [py] + sys.argv)
    sys.exit("PyQt6 is still not importable after the package step. If the package manager reported an error above, "
             "install your distribution's PyQt6 package yourself; if you use a virtualenv, run: /usr/bin/python3 " + sys.argv[0])


if __name__ == "__main__":
    if not INSTALLER.exists():
        sys.exit(f"Install-Linux.sh not found next to this script ({REPO}).")
    ensure_pyqt6()
    if "--bootstrap-only" in sys.argv:
        print("PyQt6 is installed.")
        sys.exit(0)

from PyQt6.QtCore import QEventLoop, QObject, QProcess, QProcessEnvironment, QSocketNotifier, Qt, QTimer, pyqtSignal
from PyQt6.QtGui import QFontDatabase
from PyQt6.QtWidgets import (QApplication, QButtonGroup, QCheckBox, QFileDialog, QGroupBox, QHBoxLayout, QInputDialog,
                             QLabel, QLineEdit, QMessageBox, QPlainTextEdit, QProgressBar, QProgressDialog,
                             QPushButton, QRadioButton, QVBoxLayout, QWizard, QWizardPage)

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
P_START, P_EXISTING, P_SOURCE, P_OPTIONS, P_SUMMARY, P_RUN = range(6)

ACTIONS = [
    ("install", "Install (or reinstall) WallpaperChanger", "Dependencies, scripts, wallpapers, themes.", None),
    ("update_scripts", "Update the installed scripts", "Copies only new and changed scripts.", "--update-scripts"),
    ("update_wallpapers", "Sync wallpapers from the repo", "Copies only new and updated wallpapers.", "--update-wallpapers"),
    ("thumbnails", "Install the thumbnail watcher", "Keeps the picker's thumbnails up to date automatically.", "--thumbnails"),
    ("zen", "Set up Zen Browser live theme reload", "Needs sudo and a download.", "--zen-hotreload"),
]


def label(text, wrap=True, bold=False):
    lab = QLabel(text)
    lab.setWordWrap(wrap)
    if bold:
        f = lab.font()
        f.setBold(True)
        lab.setFont(f)
    return lab


class StartPage(QWizardPage):
    def __init__(self):
        super().__init__()
        self.setTitle("WallpaperChanger")
        self.setSubTitle("What would you like to do?")
        lay = QVBoxLayout(self)
        self.group = QButtonGroup(self)
        self.radios = {}
        for i, (key, title, desc, _flag) in enumerate(ACTIONS):
            rb = QRadioButton(title)
            rb.setToolTip(desc)
            self.group.addButton(rb, i)
            self.radios[key] = rb
            lay.addWidget(rb)
            lay.addWidget(label("    " + desc))
        self.radios["install"].setChecked(True)
        lay.addStretch()
        self.note = label("")
        lay.addWidget(self.note)
        self.initializePage()

    def initializePage(self):
        """Which maintenance actions make sense depends on what is installed right now."""
        installed = CONFIG_DIR.is_dir()
        for key in ("update_scripts", "thumbnails"):
            self.radios[key].setEnabled(installed)
        self.radios["update_wallpapers"].setEnabled(WALLS_DIR.is_dir())
        if not self.group.checkedButton().isEnabled():
            self.radios["install"].setChecked(True)
        self.note.setText("WallpaperChanger is already installed on this system." if installed else "")

    def action(self):
        return ACTIONS[self.group.checkedId()][0]

    def nextId(self):
        if self.action() != "install":
            return P_RUN
        return P_EXISTING if self.wizard().needs_existing_page() else P_SOURCE


class ExistingPage(QWizardPage):
    def __init__(self):
        super().__init__()
        self.setTitle("Existing files found")
        self.setSubTitle("Choose what happens to what is already on this system. Nothing is deleted unless you say so.")
        lay = QVBoxLayout(self)
        self.cfg_group = self.wall_group = None
        if CONFIG_DIR.is_dir():
            box = QGroupBox(f"{CONFIG_DIR}")
            v = QVBoxLayout(box)
            self.cfg_group = QButtonGroup(self)
            for i, text in enumerate(["Update the scripts and keep my settings",
                                      "Remove it and install clean",
                                      "Leave the installed scripts untouched"]):
                rb = QRadioButton(text)
                self.cfg_group.addButton(rb, i)
                v.addWidget(rb)
            self.cfg_group.button(0).setChecked(True)
            self.cfg_group.button(1).setStyleSheet("color: #c0392b")
            lay.addWidget(box)
        if WALLS_DIR.is_dir():
            box = QGroupBox(f"{WALLS_DIR}")
            v = QVBoxLayout(box)
            self.wall_group = QButtonGroup(self)
            for i, text in enumerate(["Keep my wallpapers and add/update from the source",
                                      "Keep them and copy nothing",
                                      "DELETE everything in this folder first, then copy"]):
                rb = QRadioButton(text)
                self.wall_group.addButton(rb, i)
                v.addWidget(rb)
            self.wall_group.button(0).setChecked(True)
            self.wall_group.button(2).setStyleSheet("color: #c0392b")
            lay.addWidget(box)
        self.make_pictures = None
        if not PICTURES.is_dir():
            self.make_pictures = QCheckBox(f"Create {PICTURES} (it does not exist)")
            self.make_pictures.setChecked(True)
            lay.addWidget(self.make_pictures)
        lay.addStretch()

    def answers(self) -> dict:
        a = {}
        if self.cfg_group:
            c = self.cfg_group.checkedId()
            a["DELETE_CONFIG_DIR"] = yn(c == 1)
            a["COPY_SCRIPTS"] = yn(c == 0)
        if self.wall_group:
            w = self.wall_group.checkedId()
            a["DELETE_WALLPAPERS_DIR"] = yn(w == 2)
            a["COPY_WALLPAPERS"] = yn(w in (0, 2))
        if self.make_pictures:
            a["CREATE_PICTURES_DIR"] = yn(self.make_pictures.isChecked())
            a["COPY_WALLPAPERS"] = yn(self.make_pictures.isChecked())
        return a

    def describe(self) -> list:
        out = []
        if self.cfg_group:
            out.append(["- Installed scripts: updated, settings kept", "- Installed scripts: REMOVED, then installed clean",
                        "- Installed scripts: left untouched"][self.cfg_group.checkedId()])
        if self.wall_group:
            out.append(["- Your wallpapers: kept, new ones added", "- Your wallpapers: kept, nothing copied",
                        f"- {WALLS_DIR}: EVERYTHING DELETED first"][self.wall_group.checkedId()])
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
        self.status = label("")
        self.folder = QLineEdit()
        self.folder.setPlaceholderText("Folder containing sfw/ (and optionally nsfw/)")
        browse = QPushButton("Browse...")
        browse.clicked.connect(self._browse)
        self.url = QLineEdit()
        self.url.setPlaceholderText("https://github.com/user/wallpapers.git")
        self.existing = REPO_WALLS.exists() or REPO_WALLS.is_symlink()   # there before the wizard started
        self.created = False                                            # set up by this page

        if self.existing:
            self.lay.addWidget(label(f"Using the wallpapers already set up at {REPO_WALLS}."))
            self.lay.addWidget(self.status)
        else:
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

    def initializePage(self):
        if self.existing:
            bad = query_source(REPO_WALLS)["invalid"]
            self.status.setText("Its structure is invalid, so the installer will fall back to the bundled wallpapers.\n\n" + RULES
                                if bad else "Its structure looks valid.")

    def source_dir(self) -> Path:
        return REPO_WALLS if (REPO_WALLS.exists() or REPO_WALLS.is_symlink()) else DEFAULT_WALLS

    def validatePage(self) -> bool:
        if self.existing:
            return True
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
        self.setTitle("Options")
        self.lay = QVBoxLayout(self)
        self.checks = []
        self.ratios_box = None

    def initializePage(self):
        while self.lay.count():
            item = self.lay.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        self.checks = []
        src = self.wizard().page(P_SOURCE).source_dir()
        q = query_source(src)
        if q["invalid"]:                                       # same fallback the installer applies
            src = DEFAULT_WALLS
            q = query_source(src)
        self.q = q
        self.setSubTitle("Choose the aspect ratios to install and a few extras.")
        if len(q["ratios"]) > 1:
            suggested = q["suggested"] or qt_screen_fallback(src, q["ratios"])
            self.lay.addWidget(label("Aspect ratios to install" + (" (pre-ticked to match your displays):" if suggested else ":"), bold=True))
            if q["info"]:
                self.lay.addWidget(label("\n".join(q["info"]).strip()))
            for r in q["ratios"]:
                cb = QCheckBox(r + ("   (connected display)" if r in suggested else ""))
                cb.ratio = r
                cb.setChecked(r in suggested if suggested else True)
                self.checks.append(cb)
                self.lay.addWidget(cb)
        else:
            only = q["ratios"][0] if q["ratios"] else "-"
            self.lay.addWidget(label(f"Aspect ratio: only {only} is available, so that is what will be installed."))
        self.nsfw = QCheckBox("Also install the NSFW wallpapers")
        self.nsfw.setVisible(q["nsfw"])
        self.zen = QCheckBox("Set up Zen Browser live theme reload if Zen is found (needs sudo and a download)")
        self.apply = QCheckBox("Apply a random wallpaper when finished (programs may close and reopen to take the theme)")
        self.apply.setChecked(True)
        for w in (self.nsfw, self.zen, self.apply):
            self.lay.addWidget(w)
        self.lay.addStretch()

    def chosen_ratios(self):
        return [cb.ratio for cb in self.checks if cb.isChecked()]

    def validatePage(self):
        if self.checks and not self.chosen_ratios():
            QMessageBox.information(self, "Aspect ratios", "Tick at least one aspect ratio.")
            return False
        return True

    def answers(self) -> dict:
        a = {"NSFW": yn(self.nsfw.isChecked()), "APPLY_NOW": yn(self.apply.isChecked())}
        if self.checks:
            a["RATIOS"] = " ".join(self.chosen_ratios())
        return a


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
        lines = list(w.page(P_EXISTING).describe())
        src = w.page(P_SOURCE).source_dir()
        lines.append(f"- Wallpapers from: {src}")
        if o.checks:
            lines.append("- Aspect ratios: " + ", ".join(o.chosen_ratios()))
        if o.nsfw.isChecked():
            lines.append("- NSFW wallpapers included")
        if o.zen.isChecked():
            lines.append("- Zen live theme reload (if Zen is found)")
        lines.append("- A random wallpaper is applied at the end" if o.apply.isChecked() else "- No wallpaper is applied at the end")
        self.text.setText("This will run the installer with these choices:\n\n" + "\n".join(lines) +
                          "\n\nMissing packages are installed with your package manager; a dialog will ask for your "
                          "password when it is needed.")
        w.setButtonText(QWizard.WizardButton.CommitButton, "Install")


class RunPage(QWizardPage):
    def __init__(self):
        super().__init__()
        self.setTitle("Working")
        self.done = False
        self.runner = None
        lay = QVBoxLayout(self)
        self.status = label("Starting...")
        self.bar = QProgressBar()
        self.bar.setRange(0, 0)
        mono = QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont)
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setFont(mono)
        self.log.setMaximumBlockCount(5000)
        self.liveline = QLabel()                    # the line still being written: progress bars, prompts
        self.liveline.setFont(mono)
        self.liveline.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        lay.addWidget(self.status)
        lay.addWidget(self.bar)
        lay.addWidget(self.log, 1)
        lay.addWidget(self.liveline)

    def isComplete(self):
        return self.done

    def initializePage(self):
        w = self.wizard()
        self.setSubTitle(w.run_title())
        self.done = False
        self.log.clear()
        self.liveline.clear()
        env = dict(os.environ, TERM="xterm-256color", **w.run_env())
        self.runner = PtyRunner(["bash", str(INSTALLER), *w.run_args()], env, str(REPO), self)
        self.runner.output.connect(self._output)
        self.runner.prompt.connect(self._prompt)
        self.runner.finished.connect(self._finished)
        self.runner.start()

    def _output(self, lines, live):
        for ln in lines:
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
        if rc == 0:
            self.status.setText("Done.")
            self.setTitle("Finished")
        else:
            self.status.setText(f"The installer stopped with exit code {rc} - see the log above.")
            self.setTitle("Something went wrong")
        w = self.wizard()
        w.button(QWizard.WizardButton.CancelButton).setEnabled(False)
        self.completeChanged.emit()


class InstallerWizard(QWizard):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("WallpaperChanger installer")
        self.setWizardStyle(QWizard.WizardStyle.ModernStyle)
        self.setOption(QWizard.WizardOption.NoBackButtonOnLastPage, True)
        self.resize(780, 600)
        self.setPage(P_START, StartPage())
        self.setPage(P_EXISTING, ExistingPage())
        self.setPage(P_SOURCE, SourcePage())
        self.setPage(P_OPTIONS, OptionsPage())
        self.setPage(P_SUMMARY, SummaryPage())
        self.setPage(P_RUN, RunPage())

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
        env = {f"WC_ANSWER_{k}": v for k, v in a.items()}
        env["ZEN_HOTRELOAD_AUTO"] = "yes" if self.page(P_OPTIONS).zen.isChecked() else "no"
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
