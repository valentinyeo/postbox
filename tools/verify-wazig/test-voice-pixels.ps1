param([string]$Partial = '', [string]$Full = '')
$ErrorActionPreference = 'Stop'
Add-Type -Path @("$PSScriptRoot/voice.cs", "$PSScriptRoot/voice-pixels-test.cs")
[VoicePixelsTest]::Run()
if ([bool]$Partial -ne [bool]$Full) { throw 'Supply both saved screenshots' }
if ($Partial) {
    Add-Type -AssemblyName System.Drawing
    $a = [Drawing.Bitmap]::new((Resolve-Path $Partial).Path)
    $b = [Drawing.Bitmap]::new((Resolve-Path $Full).Path)
    try {
        if ($a.Width -ne $b.Width -or $a.Height -ne $b.Height -or $a.Width -lt 1024 -or $a.Height -lt 654) { throw 'Saved screenshot geometry differs' }
        $width = 723; $height = 631; $stride = $width * 4
        $first = [byte[]]::new($stride * $height)
        $second = [byte[]]::new($stride * $height)
        $raw = 0; $maxDelta = 0
        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $p = $a.GetPixel($x + 301, $y + 23); $q = $b.GetPixel($x + 301, $y + 23)
                $offset = $y * $stride + $x * 4
                $first[$offset] = $p.B; $first[$offset + 1] = $p.G; $first[$offset + 2] = $p.R; $first[$offset + 3] = $p.A
                $second[$offset] = $q.B; $second[$offset + 1] = $q.G; $second[$offset + 2] = $q.R; $second[$offset + 3] = $q.A
                $delta = [Math]::Max([Math]::Abs([int]$p.R - [int]$q.R), [Math]::Max([Math]::Abs([int]$p.G - [int]$q.G), [Math]::Abs([int]$p.B - [int]$q.B)))
                if ($delta -gt 0) { $raw++ }
                $maxDelta = [Math]::Max($maxDelta, $delta)
            }
        }
        $canvas = [VerifyVoice+Rect]::new(); $canvas.Right = $width; $canvas.Bottom = $height
        $result = [VerifyVoice]::Check($first, $second, $width, $height, $stride, $canvas, 0, 0, [VerifyVoice+Rect[]]@($canvas), [VerifyVoice+Item[]]@(), 96)
        if ($raw -ne 23 -or $maxDelta -ne 1 -or $result.differing -ne 0 -or $result.problems.Count -ne 0) { throw "Saved screenshots unexpected: raw=$raw max=$maxDelta differing=$($result.differing)" }
        Write-Host "SAVED VOICE SCREENSHOTS: raw=$raw max=$maxDelta significant=$($result.differing)"
    } finally { $a.Dispose(); $b.Dispose() }
}
