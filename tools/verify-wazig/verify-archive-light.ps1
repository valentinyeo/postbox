$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Light palette verification requires GitHub Actions' }
$path = Join-Path $PSScriptRoot '../../src/theme.zig'
$original = [IO.File]::ReadAllText($path)
$pattern = '(?s)(pub const amoled: Palette = \.\{)(.*?)(\n\};)'
$match = [regex]::Match($original, $pattern)
if (-not $match.Success) { throw 'AMOLED palette declaration missing' }
$colours = [regex]::Matches($match.Groups[2].Value, 'hex\(0x([0-9a-f]{6})\)')
if ($colours.Count -ne 16) { throw 'Unexpected AMOLED colour token count' }
$inverted = [regex]::Replace($match.Groups[2].Value, 'hex\(0x([0-9a-f]{6})\)', {
    param($colour)
    'hex(0x{0:x6})' -f (0xffffff - [Convert]::ToInt32($colour.Groups[1].Value, 16))
})
$replacement = $match.Groups[1].Value + $inverted + $match.Groups[3].Value
try {
    [IO.File]::WriteAllText($path, $original.Substring(0, $match.Index) + $replacement + $original.Substring($match.Index + $match.Length))
    & zig build '-Dtarget=x86_64-windows-gnu' --release=small '-Dversion=0.0.526' --prefix zig-out-light
    if ($LASTEXITCODE -ne 0) { throw 'Light fixture build failed' }
} finally {
    [IO.File]::WriteAllText($path, $original)
}
$evidence = 'verification-evidence/light'
New-Item $evidence -ItemType Directory -Force | Out-Null
@{ kind = 'inverted AMOLED fixture palette'; original = $match.Value; light = $replacement; production_rendering = $true } |
    ConvertTo-Json | Set-Content (Join-Path $evidence 'fixture-palette.json')
& pwsh -NoProfile -File "$PSScriptRoot/run.ps1" -Feature show-archived -Bin zig-out-light/bin -Evidence $evidence
if ($LASTEXITCODE -ne 0) { throw 'Light archive presentation journey failed' }
& python "$PSScriptRoot/check-evidence.py" $evidence
if ($LASTEXITCODE -ne 0) { throw 'Light archive presentation evidence failed' }
& python "$PSScriptRoot/check-archive-presentation.py" verification-evidence --both
if ($LASTEXITCODE -ne 0) { throw 'Light and dark archive contrast proof failed' }
