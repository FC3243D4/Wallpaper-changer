; Ctrl+Alt+W: random wallpaper + theme refresh (AutoHotkey v1.1).
; Runs PowerShell 7 hidden and NOT elevated - RGB goes through the elevated
; OpenRGB server task (see Register-OpenRgbServer.ps1).
#NoEnv
#SingleInstance Force

EnvGet, localAppData, LOCALAPPDATA
scriptPath := localAppData . "\WallpaperChanger\setRandomWallpaper-WE.ps1"

^!w::
    Run, pwsh.exe -NoProfile -WindowStyle Hidden -File "%scriptPath%",, Hide UseErrorLevel
    if (ErrorLevel = "ERROR") {
        MsgBox, 16, WallpaperChanger, Could not start PowerShell 7 (pwsh.exe). Install it with: winget install Microsoft.PowerShell
    }
return
