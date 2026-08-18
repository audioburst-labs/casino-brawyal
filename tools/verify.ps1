# Casino Brawyal — one-shot verification. Non-zero exit on any failure.
# Usage: powershell -File tools/verify.ps1
# Native stderr is merged via cmd /c to avoid PS 5.1 NativeCommandError wrapping.
$ErrorActionPreference = "Continue"
$proj = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $proj "tools\godot\Godot_v4.5.2-stable_win64_console.exe"

if (-not (Test-Path $godot)) { Write-Host "FAIL: Godot console binary not found at $godot"; exit 1 }

function Run-Godot([string]$argLine) {
    $out = cmd /c "`"$godot`" $argLine 2>&1"
    $script:lastExit = $LASTEXITCODE
    return ($out -join "`n")
}

Write-Host "== 1/3 Import assets =="
$importOut = Run-Godot "--headless --path `"$proj`" --import --quit"
Write-Host $importOut
if ($lastExit -ne 0) { Write-Host "FAIL: import exited $lastExit"; exit 1 }
if ($importOut -match "SCRIPT ERROR") { Write-Host "FAIL: script errors during import"; exit 1 }

Write-Host "== 2/3 GUT tests =="
$testOut = Run-Godot "--headless --path `"$proj`" -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json"
Write-Host $testOut
if ($lastExit -ne 0) { Write-Host "FAIL: tests exited $lastExit"; exit 1 }
if ($testOut -match "SCRIPT ERROR") { Write-Host "FAIL: script errors during tests"; exit 1 }

Write-Host "== 3/3 Smoke boot =="
$smoke = Run-Godot "--headless --path `"$proj`" --quit-after 120"
Write-Host $smoke
if ($lastExit -ne 0) { Write-Host "FAIL: smoke boot exited $lastExit"; exit 1 }
if ($smoke -match "SCRIPT ERROR") { Write-Host "FAIL: script errors during smoke boot"; exit 1 }

Write-Host "== VERIFY OK =="
exit 0
