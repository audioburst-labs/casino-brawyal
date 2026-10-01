# Capture a GIF of the running game (0.121, for the Steam page).
#
#   powershell -File tools/capture_gif.ps1 -Out build/gifs/spin.gif -Frames 260 -From 60 -Every 3 `
#       -Env "CB_DEBUG_AUTORUN=1;CB_DEBUG_DRAG=1"
#
# Runs the windowed screenshot driver in sequence mode (every K-th frame from
# -From to -Frames, at the game's 60 fps), then ffmpeg builds a palette GIF.
# -Width defaults to 960; the GIF's fps is 60 / Every. -Env is a semicolon
# list of debug hooks (a string, because `powershell -File` cannot pass a
# hashtable). Needs a window and ffmpeg.
param(
    [string]$Scene = "res://scenes/main.tscn",
    [int]$Frames = 300,
    [int]$From = 1,
    [int]$Every = 3,
    [string]$Out = "build/gifs/capture.gif",
    [int]$Width = 960,
    [string]$Env = ""
)
$ErrorActionPreference = "Stop"
$godot = "tools\godot\Godot_v4.5.2-stable_win64_console.exe"
$work = Join-Path $env:TEMP ("cb_gif_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

foreach ($pair in ($Env -split ";")) {
    if ($pair -match "^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$") { Set-Item -Path ("Env:" + $Matches[1]) -Value $Matches[2] }
}
$env:CB_CAPTURE_EVERY = "$Every"
$env:CB_CAPTURE_FROM = "$From"
$seq = Join-Path $work "frame.png"
cmd /c "$godot --path . --resolution 1920x1080 -s res://tools/screenshot.gd -- $Scene $Frames $seq 2>&1" | Select-String -Pattern "sequence saved|SCRIPT ERROR" | ForEach-Object { $_.Line }
$env:CB_CAPTURE_EVERY = ""
$env:CB_CAPTURE_FROM = ""

$fps = [math]::Max(1, [math]::Round(60 / $Every))
$pattern = Join-Path $work "frame_%04d.png"
$filters = "fps=$fps,scale=${Width}:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=224:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"
& ffmpeg -y -v error -framerate $fps -i $pattern -vf $filters -loop 0 $Out
Remove-Item -Recurse -Force $work
Get-Item $Out | Select-Object Name, @{n = "MB"; e = { [math]::Round($_.Length / 1MB, 2) } }
