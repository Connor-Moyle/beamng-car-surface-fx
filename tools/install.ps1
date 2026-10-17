# Links the mod into BeamNG as an unpacked mod (a junction, so edits here are live).
param([string]$BeamUserPath = "$env:LOCALAPPDATA\BeamNG\BeamNG.drive\current")
$ErrorActionPreference = 'Stop'
$mod = Join-Path (Split-Path $PSScriptRoot -Parent) 'mod'
$target = Join-Path $BeamUserPath 'mods\unpacked\carSurfaceFx'
if (Test-Path $target) {
  if ((Get-Item $target -Force).LinkType -ne 'Junction') { throw "$target exists and is not a junction - move it away first." }
  "Already installed: $target"
} else {
  New-Item -ItemType Junction -Path $target -Target $mod | Out-Null
  "Installed: $target -> $mod"
}
