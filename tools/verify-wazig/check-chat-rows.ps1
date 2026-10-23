$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '../../src/text_draw.zig'
$current = [IO.File]::ReadAllText($path)
$mainPath = Join-Path $PSScriptRoot '../../src/main.zig'
$currentMain = [IO.File]::ReadAllText($mainPath)
$shapesPath = Join-Path $PSScriptRoot '../../src/smooth_shapes.zig'
$currentShapes = [IO.File]::ReadAllText($shapesPath)
$marker = 'test "ISSUE-462 DirectWrite paints every row-sized chat buffer"'
$start = $current.IndexOf($marker)
if ($start -lt 0) { throw 'ISSUE-462 pixel regression missing' }
$historical = (& git show '44c90f3:src/text_draw.zig') -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Historical renderer unavailable' }
$historicalMain = (& git show '44c90f3:src/main.zig') -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Historical chat painter unavailable' }
$historicalShapes = (& git show '44c90f3:src/smooth_shapes.zig') -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Historical smooth shapes unavailable' }
try {
    [IO.File]::WriteAllText($mainPath, $historicalMain)
    [IO.File]::WriteAllText($shapesPath, $historicalShapes)
    [IO.File]::WriteAllText($path, $historical + "`n" + $current.Substring($start))
    $output = & zig test src/text_draw.zig -lc -lgdi32 -luser32 -lmsimg32 --test-filter ISSUE-462 2>&1
    $exit = $LASTEXITCODE
    $output | ForEach-Object { Write-Host "negative control, old renderer must fail: $_" }
    if ($exit -eq 0 -or ($output -join "`n") -notmatch 'buffered=true name_ink=0 preview_ink=0') { throw 'Historical renderer did not reproduce the missing row text' }
    Write-Host 'ISSUE-462 OLD RENDERER REJECTED: buffered row text has zero ink'
} finally {
    [IO.File]::WriteAllText($path, $current)
    [IO.File]::WriteAllText($mainPath, $currentMain)
    [IO.File]::WriteAllText($shapesPath, $currentShapes)
}
& zig test src/text_draw.zig -lc -lgdi32 -luser32 -lmsimg32 --test-filter ISSUE-462
if ($LASTEXITCODE -ne 0) { throw 'Chat row text regression' }
Write-Host 'ISSUE-462 ROW TEXT VERIFIED: old renderer fails, current renderer paints every row'
