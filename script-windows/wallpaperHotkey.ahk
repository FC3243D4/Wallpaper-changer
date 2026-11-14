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

ToggleGui() {
    title := "Wallpaper Selector"    ; the GUI's window title starts with this (matched as a prefix)
    if WinExist(title) {
        if WinActive(title)
            WinClose(title)          ; already focused: second press closes it
        else
            WinActivate(title)       ; open but behind something: bring it to the front
        return
    }
    py := FindExe(["pythonw.exe", "pyw.exe"])
    if (py = "") {
        Notify("Python not found (needed for the picker). Install Python, then: pip install PyQt6", true)
        return
    }
    try {
        Run('"' py '" "' guiScript '"', installDir)
    } catch as err {
        Notify("Could not start the picker: " err.Message, true)
    }
}
