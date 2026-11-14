#Requires -Version 7.0
# Monitors.psm1 (Windows only) - monitor list with real pixel sizes.

Set-StrictMode -Version Latest

function Get-WcMonitors {
    # pwsh.exe is not DPI-aware, so on a scaled display System.Windows.Forms
    # would report the *scaled* size (a 4K screen at 150% looks like 2560x1440)
    # and the wrong aspect folder could be picked. Opting the process in first
    # makes Screen.Bounds return physical pixels.
    Add-Type -AssemblyName System.Windows.Forms
    if (-not ('Wc.Dpi' -as [type])) {
        Add-Type -Namespace Wc -Name Dpi -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    }
    [void][Wc.Dpi]::SetProcessDPIAware()
    $i = 0
    foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        [pscustomobject]@{ Index = $i++; Width = $s.Bounds.Width; Height = $s.Bounds.Height; Primary = $s.Primary; Name = $s.DeviceName }
    }
}

Export-ModuleMember -Function *-*
