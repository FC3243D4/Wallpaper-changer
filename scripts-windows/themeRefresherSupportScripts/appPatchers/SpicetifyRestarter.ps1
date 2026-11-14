#Requires -Version 7.0
<#
.SYNOPSIS
  Closes Spotify, runs `spicetify apply` (picks up the freshly rendered color.ini), relaunches Spotify.
.DESCRIPTION
  Port of SpicetifyRestarter.sh. Runs in the restart phase of a Full refresh.
  Spotify is only relaunched if it was running before.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$spicetify = Get-Command spicetify -ErrorAction SilentlyContinue
if (-not $spicetify) { Write-Output 'spicetify not found, skipping'; return }

$procs = @(Get-Process -Name 'Spotify' -ErrorAction SilentlyContinue)
$path = ($procs | Where-Object { $_.Path } | Select-Object -First 1).Path
foreach ($p in $procs) { try { [void]$p.CloseMainWindow() } catch { } }
$deadline = (Get-Date).AddSeconds(2)
while ((Get-Date) -lt $deadline -and ($procs | Where-Object { -not $_.HasExited })) { Start-Sleep -Milliseconds 50 }
foreach ($p in $procs) { if (-not $p.HasExited) { try { $p.Kill($true) } catch { } } }
foreach ($p in $procs) { try { [void]$p.WaitForExit(5000) } catch { } }

& $spicetify.Source apply 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Warning "spicetify apply exited with $LASTEXITCODE" }

if ($path) { Start-Process -FilePath $path | Out-Null; Write-Output 'Spotify relaunched' }
