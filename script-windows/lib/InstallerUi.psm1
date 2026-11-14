#Requires -Version 7.0
# InstallerUi.psm1 - small interactive helpers for install-Windows.ps1.
#
#   Read-MultiSelect     arrow keys + space checklist (falls back to typing numbers
#                        when there is no real console, e.g. piped input)
#   Select-AspectRatios  which aspect-ratio folders to install, like the Linux installer
#
# Both take injectable input providers so they can be driven by tests.

Set-StrictMode -Version Latest

function Resolve-RatioSelection {
    # Turns what the user typed into a list of options.
    #   ""      -> the suggested ones      "a"/"all" -> everything
    #   "1,3"   -> by number               "16-9 21-9" or "16-9,21-9" -> by name
    # Returns $null when the text can't be understood.
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string[]]$Options,
        [string[]]$Suggested = @()
    )
    $t = $Text.Trim()
    if ($t -eq '') { return @($Options | Where-Object { $_ -in $Suggested }) }     # original order
    if ($t -match '^(a|all)$') { return @($Options) }
    $picked = [System.Collections.Generic.List[string]]::new()
    foreach ($tok in ($t -split '[,\s]+' | Where-Object { $_ })) {
        if ($tok -match '^\d+$') {
            $i = [int]$tok
            if ($i -lt 1 -or $i -gt $Options.Count) { return $null }
            $name = $Options[$i - 1]
        }
        else {
            $name = $Options | Where-Object { $_ -ieq $tok } | Select-Object -First 1
            if (-not $name) { return $null }
        }
        if (-not $picked.Contains($name)) { $picked.Add($name) }
    }
    @($Options | Where-Object { $picked.Contains($_) })      # keep the original order
}

function Read-MultiSelect {
    # Checklist: Up/Down move, Space toggles, A toggles all, Enter confirms.
    # Returns the selected options in their original order.
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Options,
        [string[]]$Preselected = @(),
        [scriptblock]$KeyProvider = { [Console]::ReadKey($true) },
        [scriptblock]$LineProvider = { param($prompt) Read-Host $prompt }
    )
    $redirected = $false
    try { $redirected = [Console]::IsInputRedirected } catch { }
    $usingDefaultKeys = $PSBoundParameters.ContainsKey('KeyProvider') -eq $false

    if ($usingDefaultKeys -and $redirected) {
        # No interactive console: numbered list + typed answer.
        Write-Host $Title
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $mark = if ($Options[$i] -in $Preselected) { '*' } else { ' ' }
            Write-Host ("  {0}) [{1}] {2}" -f ($i + 1), $mark, $Options[$i])
        }
        while ($true) {
            $answer = & $LineProvider 'Numbers or names separated by commas, "a" = all, Enter = the ones marked *'
            $sel = Resolve-RatioSelection -Text $answer -Options $Options -Suggested $Preselected
            if ($null -ne $sel) { return $sel }
            Write-Host 'Could not understand that, try again.' -ForegroundColor Yellow
        }
    }

    $checked = @($Options | ForEach-Object { $_ -in $Preselected })
    $cursor = 0
    Write-Host $Title
    Write-Host '(Up/Down to move, Space to toggle, A to toggle all, Enter to confirm)' -ForegroundColor DarkGray
    $n = $Options.Count
    1..$n | ForEach-Object { Write-Host '' }                      # reserve room so the redraw never scrolls
    $top = 0
    try { $top = [Console]::CursorTop - $n; [Console]::CursorVisible = $false } catch { $top = -1 }

    $draw = {
        if ($top -ge 0) { try { [Console]::SetCursorPosition(0, $top) } catch { } }
        for ($i = 0; $i -lt $n; $i++) {
            $box = if ($checked[$i]) { '[x]' } else { '[ ]' }
            $line = ' {0} {1} ' -f $box, $Options[$i]
            if ($i -eq $cursor) { Write-Host $line -ForegroundColor Black -BackgroundColor Gray }
            else { Write-Host $line }
        }
    }
    try {
        while ($true) {
            & $draw
            $key = & $KeyProvider
            switch ($key.Key) {
                'UpArrow' { $cursor = ($cursor - 1 + $n) % $n }
                'DownArrow' { $cursor = ($cursor + 1) % $n }
                'Spacebar' { $checked[$cursor] = -not $checked[$cursor] }
                'A' { $all = -not (@($checked | Where-Object { -not $_ }).Count -eq 0); for ($i = 0; $i -lt $n; $i++) { $checked[$i] = $all } }
                'Enter' { break }
            }
            if ($key.Key -eq 'Enter') { break }
        }
    }
    finally { try { [Console]::CursorVisible = $true } catch { } }
    @(for ($i = 0; $i -lt $n; $i++) { if ($checked[$i]) { $Options[$i] } })
}

function Select-AspectRatios {
    # Which aspect-ratio folders to install. Mirrors the Linux installer:
    #   * -All, or only one ratio available -> everything, no question
    #   * -Requested (e.g. -AspectRatios 16-9,21-9) -> exactly those (unknown names are reported and ignored)
    #   * otherwise a checklist; nothing ticked -> everything (so the library is never left empty)
    # -Suggested (ratios of the connected monitors, previous choice) are pre-ticked.
    param(
        [Parameter(Mandatory)][string[]]$Available,
        [string[]]$Requested = @(),
        [switch]$All,
        [string[]]$Suggested = @(),
        [scriptblock]$KeyProvider,
        [scriptblock]$LineProvider
    )
    if ($All -or $Available.Count -le 1) { return @($Available) }

    if ($Requested.Count -gt 0) {
        $valid = @($Available | Where-Object { $a = $_; $Requested | Where-Object { $_ -ieq $a } })
        $unknown = @($Requested | Where-Object { $r = $_; -not ($Available | Where-Object { $_ -ieq $r }) })
        if ($unknown.Count -gt 0) { Write-Warning ("Unknown aspect ratio(s) ignored: {0}. Available: {1}" -f ($unknown -join ', '), ($Available -join ', ')) }
        if ($valid.Count -gt 0) { return $valid }
        Write-Warning 'None of the requested aspect ratios exist - installing all of them instead.'
        return @($Available)
    }

    $pre = @($Suggested | Where-Object { $s = $_; $Available | Where-Object { $_ -ieq $s } })
    if ($pre.Count -eq 0) { $pre = @($Available) }
    $splat = @{ Title = 'Multiple aspect ratios were found. Select which ones to install:'; Options = $Available; Preselected = $pre }
    if ($KeyProvider) { $splat.KeyProvider = $KeyProvider }
    if ($LineProvider) { $splat.LineProvider = $LineProvider }
    $chosen = @(Read-MultiSelect @splat)
    if ($chosen.Count -eq 0) {
        Write-Host 'No aspect ratios selected - installing all of them instead.'
        return @($Available)
    }
    $chosen
}

Export-ModuleMember -Function *-*
