; -------------------------
; HOTKEY: CTRL + ALT + W
; -------------------------
^!w::
{
    ; Build full path to the PowerShell script using EnvGet
    EnvGet, userProfile, USERPROFILE
    scriptPath := userProfile . "\Documents\wallpaperScripts\setRandomWallpaper-WE.ps1"

    ; Verify the script exists
    if !FileExist(scriptPath)
    {
        MsgBox, 16, Error, PowerShell script not found:`n%scriptPath%
        return
    }

    ; Run PowerShell silently with admin (if needed)
    Run, *RunAs powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%scriptPath%", , Hide
}
return