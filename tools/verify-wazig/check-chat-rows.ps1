$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '../../src/text_draw.zig'
$current = [IO.File]::ReadAllText($path)
$marker = 'test "ISSUE-462 DirectWrite paints every row-sized chat buffer"'
$start = $current.IndexOf($marker)
if ($start -lt 0) { throw 'ISSUE-462 pixel regression missing' }
$historical = (& git show '44c90f3:src/text_draw.zig') -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Historical renderer unavailable' }
try {
    [IO.File]::WriteAllText($path, $historical + "`n" + $current.Substring($start))
    $output = & zig test src/text_draw.zig -lc -lgdi32 -luser32 -lmsimg32 --test-filter ISSUE-462 2>&1
    $exit = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exit -eq 0 -or ($output -join "`n") -notmatch 'buffered=true name_ink=0 preview_ink=0') { throw 'Historical renderer did not reproduce the missing row text' }
    Write-Host 'ISSUE-462 OLD RENDERER REJECTED: buffered row text has zero ink'
} finally {
    [IO.File]::WriteAllText($path, $current)
}
& zig test src/text_draw.zig -lc -lgdi32 -luser32 -lmsimg32 --test-filter ISSUE-462
if ($LASTEXITCODE -ne 0) { throw 'Chat row text regression' }
Write-Host 'ISSUE-462 ROW TEXT VERIFIED: old renderer fails, current renderer paints every row'
