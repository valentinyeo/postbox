param([Parameter(Mandatory)][string]$Evidence)
. "$PSScriptRoot/harness.ps1"
if (-not (Test-Path (Join-Path $Evidence 'session.json'))) { exit 0 }
$session = Read-Session $Evidence
$app = Get-Process -Id $session.pid -ErrorAction SilentlyContinue
if ($app) {
    $app = Get-App $session
    $null = $app.CloseMainWindow()
    if (-not $app.WaitForExit(10000)) {
        Stop-Process -Id $app.Id -Force
        Assert-That ($app.WaitForExit(5000)) 'Owned process did not exit'
    }
}
if ($session.PSObject.Properties.Name -contains 'bridge_pid') {
    $bridge = Get-Process -Id $session.bridge_pid -ErrorAction SilentlyContinue
    if ($bridge) {
        Assert-That ($bridge.StartTime.ToUniversalTime().Ticks.ToString() -eq $session.bridge_start_ticks -and $bridge.Path -eq $session.bridge_exe) 'Fake bridge PID was reused'
        Stop-Process -Id $bridge.Id -Force
        Assert-That ($bridge.WaitForExit(5000)) 'Fake bridge survived cleanup'
    }
}
if (Test-Path "$($session.root)/local/Messages") {
    Copy-Item "$($session.root)/local/Messages" (Join-Path $session.evidence 'final-data') -Recurse -Force
}
$registry = "HKCU:\Software\MessagesVerification\$($session.id)"
if (Test-Path $registry) {
    Get-ItemProperty "$registry\Software\Messages" -ErrorAction SilentlyContinue | Format-List | Out-File (Join-Path $session.evidence 'preferences.txt')
    Remove-Item $registry -Recurse -Force
}
if (Test-Path $session.root) { Remove-Item $session.root -Recurse -Force }
Assert-That (-not (Test-Path $session.root)) 'Scratch data survived cleanup'
Assert-That (-not (Test-Path $registry)) 'Scratch registry survived cleanup'
Assert-That ($null -eq (Get-Process -Id $session.pid -ErrorAction SilentlyContinue)) 'Owned process survived cleanup'
'CLEANUP PASSED: owned process, scratch registry and scratch data removed; evidence retained' | Set-Content (Join-Path $session.evidence 'cleanup.txt')
