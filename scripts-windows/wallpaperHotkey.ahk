; WallpaperChanger hotkeys - AutoHotkey v2
;
;   Win+Shift+W            random wallpaper
;   Win+Ctrl+Shift+W       random SFW wallpaper
;   Win+Shift+Alt+W        random NSFW wallpaper
;   Win+W                  wallpaper picker GUI (press again to close it)
;
; Everything runs NOT elevated: RGB goes through the elevated OpenRGB server
; task (see Register-OpenRgbServer.ps1). Win+W replaces Windows' own Widgets
; shortcut while this script runs. Change the bindings in the HOTKEYS block.
#Requires AutoHotkey v2.0
#SingleInstance Force

installDir := A_ScriptDir
wallpaperScript := installDir "\setRandomWallpaper-WE.ps1"
guiScript := installDir "\WallpaperGui.py"
busy := false                       ; only one wallpaper run at a time

; ---- HOTKEYS ---------------------------------------------------------------------
#+w::SetWallpaper("")               ; Win+Shift+W
#^+w::SetWallpaper("-Filter Sfw")    ; Win+Ctrl+Shift+W
#+!w::SetWallpaper("-Filter Nsfw")   ; Win+Shift+Alt+W
#w::ToggleGui()                     ; Win+W
; ------------------------------------------------------------------------------------

Notify(text, isError := false) {
    TrayTip(text, "Wallpaper Changer", isError ? "Iconx" : "Iconi")
}

FindExe(names, extraPaths := []) {
    for p in extraPaths {
        if FileExist(p)
            return p
    }
    for dir in StrSplit(EnvGet("PATH"), ";") {
        if (dir = "")
            continue
        for name in names {
            full := RTrim(dir, "\") "\" name
            if FileExist(full)
                return full
        }
    }
    return ""
}

SetWallpaper(extraArgs) {
    global busy
    if busy                          ; a run is still in progress: ignore the extra key press
        return
    pwsh := FindExe(["pwsh.exe"], [A_ProgramFiles "\PowerShell\7\pwsh.exe"])
    if (pwsh = "") {
        Notify("PowerShell 7 (pwsh.exe) not found. Install it with: winget install Microsoft.PowerShell", true)
        return
    }
    busy := true
    try {
        cmd := '"' pwsh '" -NoProfile -ExecutionPolicy Bypass -File "' wallpaperScript '" ' extraArgs
        code := RunWait(cmd, installDir, "Hide")
        if (code != 0)
            Notify("The wallpaper script failed (exit code " code "). Run it in a terminal to see the error.", true)
    } catch as err {
        Notify("Could not start PowerShell: " err.Message, true)
    } finally {
        busy := false
    }
}

; Reads a string value from config.json (written by the installer / Install-PythonEnv).
ReadConfigString(name) {
    cfg := installDir "\config.json"
    if !FileExist(cfg)
        return ""
    text := FileRead(cfg, "UTF-8")
    if RegExMatch(text, '"' name '"\s*:\s*"((?:[^"\\]|\\.)*)"', &m)
        return StrReplace(StrReplace(m[1], '\"', '"'), "\\", "\")      ; undo JSON escaping of the path
    return ""
}

ToggleGui() {
    title := "Wallpaper Selector"    ; the GUI's window title starts with this (matched as a prefix)
    if WinExist(title) {
        if WinActive(title)
            WinClose(title)          ; already focused: second press closes it
        else
            WinActivate(title)       ; open but behind something: bring it to the front
        return
    }
    ; The interpreter the installer verified (config.json), else whatever is on PATH.
    py := ReadConfigString("pythonwExe")
    if (py = "" || !FileExist(py))
        py := FindExe(["pythonw.exe", "pyw.exe"])
    if (py = "") {
        Notify("Python not found (needed for the picker). Re-run install-Windows.ps1, it can set Python and PyQt6 up.", true)
        return
    }
    try {
        Run('"' py '" "' guiScript '"', installDir)
    } catch as err {
        Notify("Could not start the picker: " err.Message, true)
        return
    }
    ; pythonw has no console, so a crash would be invisible: tell the user if no window shows up.
    if !WinWait(title, , 12)
        Notify("The wallpaper picker did not open. Run WallpaperGui.py in a terminal to see the error.", true)
}
