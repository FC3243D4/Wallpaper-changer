#Requires -Version 7.0
# AppRestarter.ps1 - dot-source this file; it defines the stop / start phases.
#
# Port of AppRestarter.sh. Apps that cache their theme at startup are closed
# before the patchers run and relaunched afterwards - only the ones that were
# actually running. The executable to relaunch is read from the running
# process itself, so it works for any install location (user, system, scoop...).
#
#   Start-AppStopPhase    detect running apps, begin closing them (async)
#   Wait-AppStopPhase     wait until they are gone
#   Start-AppRestartPhase relaunch what was closed
#
# Grace = seconds to let an app quit on its own (CloseMainWindow) before its
# whole process tree is killed. Grace 0 = kill right away. Tray apps such as
# Vesktop ignore a window close, so they use 0, like on Linux.

$script:AppDefs = [ordered]@{
    code        = @{ Process = 'Code'; Args = @(); Grace = 0 }
    vesktop     = @{ Process = 'Vesktop'; Args = @('-m'); Grace = 0 }
    ferdium     = @{ Process = 'Ferdium'; Args = @(); Grace = 1 }
    sourcegit   = @{ Process = 'SourceGit'; Args = @(); Grace = 1 }
    # Mail clients get longer than on Linux: killing one mid-write risks its message index.
    thunderbird = @{ Process = 'thunderbird'; Args = @(); Grace = 5 }
    betterbird  = @{ Process = 'betterbird'; Args = @(); Grace = 5 }
}
$script:StopState = [ordered]@{}

function Get-AncestorPid {
    # PIDs of this process and all its parents (Windows). Used so the refresher
    # never kills the terminal / editor it is itself running inside of.
    $result = [System.Collections.Generic.HashSet[int]]::new()
    $id = $PID
    if (-not $IsWindows) { [void]$result.Add($id); return $result }
    while ($id -and $result.Add($id)) {
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
        $id = if ($parent) { [int]$parent.ParentProcessId } else { 0 }
    }
    $result
}

function Start-AppStopPhase {
    param([string[]]$Only)
    $script:StopState = [ordered]@{}
    $ancestors = Get-AncestorPid
    foreach ($name in $script:AppDefs.Keys) {
        if ($Only -and $name -notin $Only) { continue }
        $def = $script:AppDefs[$name]
        $procs = @(Get-Process -Name $def.Process -ErrorAction SilentlyContinue)
        if ($procs.Count -eq 0) { continue }
        if ($procs | Where-Object { $_.Id -in $ancestors }) {
            Write-Host "[$name] this script is running inside it - leaving it alone (close/reopen it manually to pick up the new theme)"
            continue
        }
        $path = ($procs | Where-Object { $_.Path } | Select-Object -First 1).Path
        if (-not $path) { Write-Host "[$name] running but its path is not readable (elevated?) - not restarting it"; continue }
        $job = Start-ThreadJob -ScriptBlock {
            param($procs, $grace)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            if ($grace -gt 0) {
                foreach ($p in $procs) { try { [void]$p.CloseMainWindow() } catch { } }
                while ($sw.Elapsed.TotalSeconds -lt $grace -and ($procs | Where-Object { -not $_.HasExited })) { Start-Sleep -Milliseconds 50 }
            }
            $killed = $false
            foreach ($p in $procs) { if (-not $p.HasExited) { try { $p.Kill($true); $killed = $true } catch { } } }
            foreach ($p in $procs) { try { [void]$p.WaitForExit(5000) } catch { } }
            [pscustomobject]@{ Seconds = $sw.Elapsed.TotalSeconds; Killed = $killed }
        } -ArgumentList @($procs, $def.Grace)
        $script:StopState[$name] = @{ Path = $path; Args = $def.Args; Job = $job }
    }
    $script:StopState.Keys | ForEach-Object { Write-Host "Stopping: $_" }
}

function Wait-AppStopPhase {
    foreach ($name in $script:StopState.Keys) {
        $job = $script:StopState[$name].Job
        $r = Receive-Job -Job $job -Wait -AutoRemoveJob
        if ($r) { [Console]::Error.WriteLine(('[timing] app_stop {0}: {1:N3}s{2}' -f $name, $r.Seconds, $(if ($r.Killed) { ' (killed after grace)' } else { '' }))) }
    }
}

function Start-AppRestartPhase {
    foreach ($name in $script:StopState.Keys) {
        $s = $script:StopState[$name]
        try {
            if ($s.Args.Count -gt 0) { Start-Process -FilePath $s.Path -ArgumentList $s.Args | Out-Null }
            else { Start-Process -FilePath $s.Path | Out-Null }
            Write-Host "Restarted: $name"
        }
        catch { Write-Warning "Could not restart ${name}: $($_.Exception.Message)" }
    }
    $script:StopState = [ordered]@{}
}
