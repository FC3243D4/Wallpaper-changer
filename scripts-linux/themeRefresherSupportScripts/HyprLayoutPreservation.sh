#!/usr/bin/env bash
# HyprLayoutPreservation.sh
# Saves/restores Hyprland window layout (master, dwindle, scrolling, monocle,
# including mixed setups). Same CLI as before:
#   HyprLayoutPreservation.sh save|restore [--debug]
# The implementation is the Python below, run via `python3 -` so this stays a
# single drop-in file. The four *LayoutWorkspaceRestorer.sh files and
# hyprLayoutPreservationSupportScripts/ are no longer used.
exec python3 - "$@" << 'PYEOF'
"""
HyprLayoutPreservation.sh

Saves and restores Hyprland window layout across all workspaces, so
arrangement survives events that scatter windows (e.g. a theme refresh
restarting several apps at once). Drop-in replacement for the bash
HyprLayoutPreservation.sh + the four *LayoutWorkspaceRestorer.sh files.

Same behaviour, same four layouts (master, dwindle, scrolling, monocle),
including mixed setups. What's different:

  * Talks to Hyprland's IPC socket directly instead of spawning
    hyprctl/python3/jq/sed for every query (falls back to hyprctl if the
    socket can't be reached).
  * No fixed sleeps. After every state-changing dispatch it waits for the
    compositor state (window geometry, workspaces, focus) to stop
    changing, which takes tens of milliseconds instead of 150-300 ms.
  * Windows are always targeted by their CURRENT address, resolved from
    a fresh snapshot (class match first, saved address only to break ties
    between windows of the same class -- same rule as the bash version).

Usage:
  HyprLayoutPreservation.sh save|restore [--debug]

Environment:
  HYPR_LAYOUT_SETTLE_MS   minimum wait after each dispatch (default 25).
                          Raise it if windows end up mis-ordered.
  HYPR_LAYOUT_DEBUG=1     same as --debug: log every dispatch to stderr.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

SCRATCH = "special:layoutscratch"
STATE_FILE = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "hyprLayoutState.json"
SETTLE_MS = float(os.environ.get("HYPR_LAYOUT_SETTLE_MS", "25"))
DEBUG = bool(os.environ.get("HYPR_LAYOUT_DEBUG"))


def dbg(msg: str) -> None:
    if DEBUG:
        print(msg, file=sys.stderr)


# --------------------------------------------------------------------------
# Hyprland IPC
# --------------------------------------------------------------------------

class Hypr:
    def __init__(self) -> None:
        runtime = os.environ.get("XDG_RUNTIME_DIR")
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        self.sock_path = f"{runtime}/hypr/{sig}/.socket.sock" if runtime and sig else None
        self.timeouts = 0

    # -- transport ---------------------------------------------------------
    def raw(self, command: str) -> str:
        if self.sock_path:
            try:
                return self._socket(command)
            except OSError as e:
                dbg(f"[ipc] socket failed ({e}); falling back to hyprctl")
                self.sock_path = None
        return self._hyprctl(command)

    def _socket(self, command: str) -> str:
        # Hyprland's command socket is one request per connection.
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(2.0)
            s.connect(self.sock_path)
            s.sendall(command.encode())
            chunks = []
            while True:
                data = s.recv(65536)
                if not data:
                    break
                chunks.append(data)
        return b"".join(chunks).decode(errors="replace")

    @staticmethod
    def _hyprctl(command: str) -> str:
        if command.startswith("j/"):
            argv = ["hyprctl", *command[2:].split(), "-j"]
        else:
            name, _, rest = command.partition(" ")
            argv = ["hyprctl", name] + ([rest] if rest else [])
        return subprocess.run(argv, capture_output=True, text=True).stdout

    # -- queries -----------------------------------------------------------
    def json(self, what: str):
        try:
            return json.loads(self.raw("j/" + what))
        except ValueError:
            return None

    def clients(self) -> list[dict]:
        return self.json("clients") or []

    def workspaces(self) -> list[dict]:
        return self.json("workspaces") or []

    def active_workspace_id(self):
        d = self.json("activeworkspace")
        return d.get("id") if isinstance(d, dict) else None

    def option(self, name: str) -> str:
        d = self.json("getoption " + name)
        return (d.get("str") if isinstance(d, dict) else "") or ""

    # -- mutations ---------------------------------------------------------
    def dispatch(self, expr: str) -> bool:
        reply = self.raw("dispatch " + expr).strip()
        dbg(f"  [dispatch] {expr} -> {reply or '(empty)'}")
        return reply == "ok"

    def signature(self) -> tuple:
        """Everything a dispatch can change that we care about."""
        clients = tuple(sorted(
            (c["address"], c["workspace"]["id"], c["workspace"]["name"],
             tuple(c["at"]), tuple(c["size"]))
            for c in self.clients()
        ))
        lastwin = tuple(sorted((w["id"], w.get("lastwindow")) for w in self.workspaces()))
        active = self.json("activewindow")
        active_addr = active.get("address") if isinstance(active, dict) else None
        return clients, lastwin, active_addr

    def settle(self, min_wait_ms: float | None = None, timeout: float = 0.5) -> bool:
        """Wait until compositor state stops changing (two equal snapshots)."""
        wait = (SETTLE_MS if min_wait_ms is None else min_wait_ms) / 1000.0
        start = time.monotonic()
        time.sleep(wait)
        prev = self.signature()
        while time.monotonic() - start < timeout:
            time.sleep(0.01)
            cur = self.signature()
            if cur == prev:
                return True
            prev = cur
        self.timeouts += 1
        dbg("  [settle] state still changing after timeout, continuing")
        return False

    def run(self, expr: str, min_wait_ms: float | None = None) -> None:
        self.dispatch(expr)
        self.settle(min_wait_ms)


# --------------------------------------------------------------------------
# Lua dispatch expressions (Hyprland 0.55+)
# --------------------------------------------------------------------------

def lua_focus_ws(ws) -> str:
    return f"hl.dsp.focus({{ workspace = {ws} }})"


def lua_focus_win(addr: str) -> str:
    return f'hl.dsp.focus({{ window = "address:{addr}", follow = false }})'


def lua_move_ws(addr: str, ws) -> str:
    target = f'"{ws}"' if isinstance(ws, str) else str(ws)
    return (f'hl.dsp.window.move({{ workspace = {target}, '
            f'window = "address:{addr}", follow = false }})')


def lua_move_dir(direction: str) -> str:
    return f'hl.dsp.window.move({{ direction = "{direction}" }})'


def lua_layout(cmd: str) -> str:
    return f'hl.dsp.layout("{cmd}")'


# --------------------------------------------------------------------------
# Shared helpers
# --------------------------------------------------------------------------

def ref(c: dict) -> dict:
    return {"address": c["address"], "class": c["class"]}


def geom(c: dict) -> dict:
    return {**ref(c), "at": list(c["at"]), "size": list(c["size"])}


def pick_master(ws_clients: list[dict], orientation: str) -> dict:
    max_area = max(c["size"][0] * c["size"][1] for c in ws_clients)
    candidates = [c for c in ws_clients if c["size"][0] * c["size"][1] == max_area]
    if len(candidates) == 1:
        return candidates[0]
    # Equal-area tie (e.g. a plain 2-window 50/50 split): fall back to
    # position along the axis master:orientation puts the master pane on.
    if orientation == "right":
        return max(candidates, key=lambda c: c["at"][0])
    if orientation == "top":
        return min(candidates, key=lambda c: c["at"][1])
    if orientation == "bottom":
        return max(candidates, key=lambda c: c["at"][1])
    return min(candidates, key=lambda c: c["at"][0])  # left / center / unknown


def resolve(saved: dict, pool: list[dict]) -> dict | None:
    """Find the live window for a saved (address, class) entry.

    0 class matches -> None. 1 match -> that window (address may be stale,
    which is fine). 2+ matches -> only usable if the saved address is still
    among them; otherwise ambiguous -> None.
    """
    cls = saved["class"].lower()
    matches = [c for c in pool if cls in c.get("class", "").lower()]
    if len(matches) == 1:
        return matches[0]
    for c in matches:
        if c["address"] == saved["address"]:
            return c
    return None


def windows_of(ws: dict) -> list[dict]:
    if ws["layout"] == "master":
        return ([ws["master"]] if ws.get("master") else []) + ws.get("slaves", [])
    return ws.get("windows", [])


def on_ws(clients: list[dict], wid: int) -> list[dict]:
    return [c for c in clients if c["workspace"]["id"] == wid]


# --------------------------------------------------------------------------
# SAVE
# --------------------------------------------------------------------------

def snapshot_workspace(wid: int, layout: str, ws_clients: list[dict], orientation: str) -> dict:
    base = {"id": wid, "layout": layout}

    if layout == "master":
        if len(ws_clients) == 1:
            return {**base, "master": ref(ws_clients[0]), "slaves": []}
        master = pick_master(ws_clients, orientation)
        slaves = sorted((c for c in ws_clients if c["address"] != master["address"]),
                        key=lambda c: (c["at"][1], c["at"][0]))
        return {**base, "master": ref(master), "slaves": [ref(c) for c in slaves]}

    if layout == "scrolling":
        # Windows in one column share the same left-edge x and stack
        # vertically: columns left-to-right, rows top-to-bottom.
        cols: dict[int, list[dict]] = {}
        for c in ws_clients:
            cols.setdefault(c["at"][0], []).append(c)
        windows = []
        for col_idx, x in enumerate(sorted(cols)):
            for row_idx, c in enumerate(sorted(cols[x], key=lambda c: c["at"][1])):
                windows.append({**geom(c), "col": col_idx, "row": row_idx})
        return {**base, "windows": windows}

    # dwindle (or any unrecognised layout): raster order as a proxy for
    # insertion order, plus geometry for the grid-correction pass.
    ordered = sorted(ws_clients, key=lambda c: (c["at"][1], c["at"][0]))
    return {**base, "windows": [geom(c) for c in ordered]}


def capture_monocle(h: Hypr, wid: int) -> dict:
    """Monocle has no passive geometry signal: walk cyclenext and record
    which window becomes visible at each step."""
    print(f"Capturing monocle cycle order for workspace {wid}...")
    h.run(lua_focus_ws(wid), min_wait_ms=50)

    total = len(on_ws(h.clients(), wid))
    order: list[dict] = []
    start = None
    for i in range(total):
        cur = next((c for c in on_ws(h.clients(), wid) if c.get("visible")), None)
        if cur is None:
            break
        if i == 0:
            start = cur["address"]
        elif cur["address"] == start:
            break  # cycled back to the start
        order.append(ref(cur))
        h.run(lua_layout("cyclenext"))
    return {"id": wid, "layout": "monocle", "windows": order}


def save_layout(h: Hypr) -> None:
    current_ws = h.active_workspace_id()
    default_layout = h.option("general:layout") or "dwindle"
    orientation = h.option("master:orientation")
    print(f"Current workspace: {current_ws}")
    print(f"Default layout mode: {default_layout}")

    ws_layouts = {w["id"]: w["tiledLayout"] for w in h.workspaces() if w.get("tiledLayout")}
    if ws_layouts:
        print("Live per-workspace layouts: " +
              ",".join(f"{k}={v}" for k, v in ws_layouts.items()))

    by_ws: dict[int, list[dict]] = {}
    for c in h.clients():
        wid = c["workspace"]["id"]
        if wid > 0:  # skip special workspaces
            by_ws.setdefault(wid, []).append(c)

    state = {"current_workspace": current_ws, "default_layout": default_layout, "workspaces": []}
    monocle_ids = []
    for wid, ws_clients in sorted(by_ws.items()):
        layout = ws_layouts.get(wid, default_layout)
        if layout == "monocle":
            monocle_ids.append(wid)
            continue
        state["workspaces"].append(snapshot_workspace(wid, layout, ws_clients, orientation))

    # Monocle capture briefly switches workspaces; every other layout above
    # was captured passively with no side effects.
    for wid in monocle_ids:
        state["workspaces"].append(capture_monocle(h, wid))
    if monocle_ids:
        h.run(lua_focus_ws(current_ws), min_wait_ms=50)

    if state["workspaces"]:
        STATE_FILE.write_text(json.dumps(state))
        print("Layout saved for workspaces:")
        for ws in state["workspaces"]:
            print(ws["id"])
    else:
        print("No layouts found to save")
        STATE_FILE.unlink(missing_ok=True)


# --------------------------------------------------------------------------
# RESTORE -- per-layout workers
# --------------------------------------------------------------------------

def evict_all(h: Hypr, addrs: list[str]) -> None:
    """Send windows to the scratch workspace so Hyprland forgets their old
    position in the layout, then let things settle once."""
    for addr in addrs:
        h.dispatch(lua_move_ws(addr, SCRATCH))
    h.settle()


def restore_master(h: Hypr, ws: dict, orientation: str) -> None:
    wid = ws["id"]
    master_saved = ws.get("master")
    if not master_saved:
        return
    slaves_saved = ws.get("slaves", [])
    print(f"Restoring workspace {wid} (master: {master_saved['class']})")

    clients = h.clients()
    master_cur = resolve(master_saved, clients)
    if master_cur is None:
        print(f"  Skipping master {master_saved['class']} (not currently open, or ambiguous duplicates)")
    if not slaves_saved:
        return  # single-window workspace: nothing to order

    # Only windows that are actually open take part in slot ordering, so a
    # closed window doesn't leave a gap in the target slots.
    targets = []
    for s in slaves_saved:
        if resolve(s, clients) is None:
            print(f"  Skipping {s['class']} (not currently open, or ambiguous duplicates)")
        else:
            targets.append(s)

    # Step 1: promote the right window to master, only if needed.
    if master_cur is not None:
        ws_clients = on_ws(clients, wid)
        if ws_clients:
            current_master = pick_master(ws_clients, orientation)
            if current_master["address"] != master_cur["address"]:
                print(f"  Promoting {master_saved['class']} to master on ws {wid}")
                h.run(lua_focus_win(master_cur["address"]))
                h.run(lua_layout("swapwithmaster master"))

    # Step 2: fill slave slots in order. Each iteration needs a FRESH
    # snapshot -- an earlier swap changes slot order for everyone after it.
    for target_slot, saved in enumerate(targets):
        clients = h.clients()
        cur = resolve(saved, clients)
        ws_clients = on_ws(clients, wid)
        if cur is None or not ws_clients:
            continue
        master = pick_master(ws_clients, orientation)
        slaves = sorted((c for c in ws_clients if c["address"] != master["address"]),
                        key=lambda c: (c["at"][1], c["at"][0]))
        addrs = [c["address"] for c in slaves]
        if cur["address"] not in addrs:
            continue
        current_slot = addrs.index(cur["address"])
        swaps = current_slot - target_slot
        if swaps > 0:
            print(f"  Moving slot {current_slot} to slot {target_slot}")
            h.run(lua_focus_win(cur["address"]))
            for _ in range(swaps):
                h.run(lua_layout("swapprev"))


def correct_dwindle_geometry(h: Hypr, wid: int, entries: list[dict]) -> None:
    """Directional-move corrections for grid placement (e.g. 2x2 quarters).
    Buckets into lo/hi halves rather than exact pixels -- that's all a
    directional move can influence."""
    if len(entries) < 2:
        return
    xs = [e["at"][0] for e in entries]
    ys = [e["at"][1] for e in entries]
    has_h = (max(xs) - min(xs)) > 15
    has_v = (max(ys) - min(ys)) > 15
    mid_x = (min(xs) + max(xs)) / 2
    mid_y = (min(ys) + max(ys)) / 2

    def bucket(v, mid):
        return "lo" if v < mid else "hi"

    for _ in range(4):
        ws_clients = on_ws(h.clients(), wid)
        if not ws_clients:
            return
        actions: list[tuple[str, str]] = []
        for e in entries:
            cur = resolve(e, ws_clients)
            if cur is None:
                continue
            if has_h and bucket(e["at"][0], mid_x) != bucket(cur["at"][0], mid_x):
                actions.append((cur["address"], "l" if bucket(e["at"][0], mid_x) == "lo" else "r"))
            if has_v and bucket(e["at"][1], mid_y) != bucket(cur["at"][1], mid_y):
                actions.append((cur["address"], "u" if bucket(e["at"][1], mid_y) == "lo" else "d"))
        if not actions:
            break
        for addr, direction in actions:
            print(f"  Adjusting grid position: focusing address:{addr}, move {direction}")
            h.run(lua_focus_win(addr))
            h.run(lua_move_dir(direction))


def restore_dwindle(h: Hypr, ws: dict) -> None:
    wid = ws["id"]
    entries = ws.get("windows", [])
    print(f"Restoring workspace {wid} (dwindle, {len(entries)} windows)")
    if len(entries) < 2:
        return

    clients = h.clients()
    movable = []
    for e in entries:
        cur = resolve(e, clients)
        if cur is None:
            print(f"  Skipping {e['class']} (not currently open, or ambiguous duplicates)")
        else:
            movable.append(cur["address"])
    if not movable:
        return

    evict_all(h, movable)
    # Reinsert one at a time in saved order. Dwindle splits off whichever
    # window is focused, so each one must be focused right after it lands.
    for addr in movable:
        h.run(lua_move_ws(addr, wid))
        h.run(lua_focus_win(addr))

    correct_dwindle_geometry(h, wid, entries)


def restore_scrolling(h: Hypr, ws: dict) -> None:
    """Scrolling: a window arriving on the workspace always becomes its own
    new column; `move left` merges the focused window into the previous
    column (appended at its bottom). So: evict everyone, reinsert in
    column-major order, merging every non-first window of a column left.
    Row order inside a column is then fixed by bounded up/down moves."""
    wid = ws["id"]
    entries = ws.get("windows", [])
    print(f"Restoring workspace {wid} (scrolling, {len(entries)} windows)")
    if len(entries) <= 1:
        return

    clients = h.clients()
    movable: list[tuple[dict, str]] = []
    for e in entries:
        cur = resolve(e, clients)
        if cur is None:
            print(f"  Skipping {e['class']} (not currently open, or ambiguous duplicates)")
        else:
            movable.append((e, cur["address"]))
    if not movable:
        return

    evict_all(h, [addr for _, addr in movable])

    prev_col = None
    for e, addr in movable:
        h.run(lua_move_ws(addr, wid))
        h.run(lua_focus_win(addr))
        if e["col"] == prev_col:
            h.run(lua_move_dir("l"))
        prev_col = e["col"]

    # Column membership is right; row order within a column may not be.
    for _ in range(5):
        corrected = False
        for e, addr in movable:
            ws_clients = on_ws(h.clients(), wid)
            target = next((c for c in ws_clients if c["address"] == addr), None)
            if target is None:
                continue
            column = sorted((c for c in ws_clients if c["at"][0] == target["at"][0]),
                            key=lambda c: c["at"][1])
            rank = [c["address"] for c in column].index(addr)
            if rank != e["row"]:
                h.run(lua_focus_win(addr))
                h.run(lua_move_dir("u" if rank > e["row"] else "d"))
                corrected = True
        if not corrected:
            break


def restore_monocle(h: Hypr, ws: dict) -> None:
    """Moving a window onto a monocle workspace always makes it the new top
    of the stack, so inserting in REVERSE saved order rebuilds the stack."""
    wid = ws["id"]
    entries = ws.get("windows", [])
    print(f"Restoring workspace {wid} (monocle, {len(entries)} windows)")
    if len(entries) <= 1:
        return

    clients = h.clients()
    addrs = []
    for e in entries:
        cur = resolve(e, clients)
        if cur is None:
            print(f"  Skipping {e['class']} (not currently open, or ambiguous duplicates)")
        else:
            addrs.append(cur["address"])
    if not addrs:
        return

    evict_all(h, addrs)
    for addr in reversed(addrs):
        h.run(lua_move_ws(addr, wid))


# --------------------------------------------------------------------------
# RESTORE
# --------------------------------------------------------------------------

def restore_layout(h: Hypr) -> None:
    if not STATE_FILE.is_file() or STATE_FILE.stat().st_size == 0:
        print("No saved layout state found, skipping restore")
        return
    state = json.loads(STATE_FILE.read_text())
    saved_ws = state["current_workspace"]
    ws_list = state["workspaces"]
    print(f"Will return to workspace: {saved_ws}")
    print(f"Saved default layout mode: {state.get('default_layout')}")

    records = [(ws["id"], w) for ws in ws_list for w in windows_of(ws)]

    # Phase 1: put every saved window on its workspace first, so ordering
    # logic never runs while a window meant for it is still elsewhere. Moves
    # don't change class/address, so one snapshot serves the whole loop and
    # a single settle at the end covers all of them.
    print("Phase 1: moving all windows to their correct workspaces...")
    clients = h.clients()
    moved = False
    for wid, saved in records:
        cur = resolve(saved, clients)
        if cur is None:
            print(f"  Skipping {saved['class']} (not currently open, or ambiguous duplicates)")
            continue
        if cur["workspace"]["id"] != wid:
            print(f"  Moving {saved['class']} from ws {cur['workspace']['id']} to ws {wid}")
            h.dispatch(lua_move_ws(cur["address"], wid))
            moved = True
    if moved:
        h.settle()

    # Phase 2: layout-specific ordering, workspace by workspace.
    print("Phase 2: restoring layout order per workspace...")
    orientation = h.option("master:orientation") if any(w["layout"] == "master" for w in ws_list) else ""
    for ws in ws_list:
        layout = ws["layout"]
        if layout == "master":
            restore_master(h, ws, orientation)
        elif layout == "scrolling":
            restore_scrolling(h, ws)
        elif layout == "monocle":
            restore_monocle(h, ws)
        else:
            restore_dwindle(h, ws)

    # Settle pass: apps with a delayed/hidden start create their real window
    # after Phase 1 and land on whatever workspace is active at that moment.
    print("Verifying window placement...")
    for _ in range(3):
        corrected = False
        clients = h.clients()
        for wid, saved in records:
            cur = resolve(saved, clients)
            if cur is not None and cur["workspace"]["id"] != wid:
                print(f"  Correcting {saved['class']}: ws {cur['workspace']['id']} -> ws {wid}")
                h.dispatch(lua_move_ws(cur["address"], wid))
                corrected = True
        if not corrected:
            break
        time.sleep(0.5)  # give late windows time to show up before re-checking

    # Return to the original workspace; retry until it sticks.
    for _ in range(5):
        if h.active_workspace_id() == saved_ws:
            break
        h.run(lua_focus_ws(saved_ws), min_wait_ms=50)

    STATE_FILE.unlink(missing_ok=True)
    print("Layout restore complete")


# --------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    global DEBUG
    if "--debug" in argv:
        DEBUG = True
    args = [a for a in argv[1:] if a != "--debug"]
    if len(args) != 1 or args[0] not in ("save", "restore"):
        print("Usage: HyprLayoutPreservation.sh save|restore [--debug]", file=sys.stderr)
        return 1

    h = Hypr()
    try:
        (save_layout if args[0] == "save" else restore_layout)(h)
    except Exception as e:  # never take the theme refresh down with us
        print(f"HyprLayoutPreservation: {args[0]} failed: {e!r}", file=sys.stderr)
        if DEBUG:
            raise
        return 1
    if h.timeouts:
        print(f"HyprLayoutPreservation: {h.timeouts} settle wait(s) hit their timeout "
              f"(rerun with --debug if the layout came out wrong)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PYEOF