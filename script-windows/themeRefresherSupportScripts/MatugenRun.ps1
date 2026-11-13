#Requires -Version 7.0
# Thin entry point so ThemeRefresher can run matugen as a parallel job.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Color)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\Matugen.psm1') -DisableNameChecking
Invoke-Matugen -Color $Color
Write-Output 'matugen templates rendered'
