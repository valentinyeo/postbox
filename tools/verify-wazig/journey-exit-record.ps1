$logPath = Join-Path $messages 'launch-log.txt'
$recordPath = Join-Path $messages 'last-exit.txt'
$window = Get-Window $session
Assert-That (-not (Test-Path $recordPath)) 'An exit record exists while the app is still running'
$before = @(Get-Content $logPath)
Assert-That (@($before | Where-Object { $_.Contains('shutdown: close requested') }).Count -eq 0) 'A close request was logged before any close'
$old = Get-App $session
$oldPid = $old.Id
Assert-That ($old.CloseMainWindow()) 'The window refused an external close request'
Assert-That ($old.WaitForExit(30000)) 'The app did not exit after the close request'
$old.Refresh()
$lines = @(Get-Content $logPath)
$closeIndex = -1
$exitIndex = -1
for ($index = 0; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -match '^\d+ shutdown: close requested uptime=\d+$') { $closeIndex = $index }
    if ($lines[$index] -match '^\d+ shutdown: clean exit code=0 reason=wm_close uptime=\d+$') { $exitIndex = $index }
}
Assert-That ($closeIndex -ge 0) 'The close request was not logged' -AppExited
Assert-That ($exitIndex -gt $closeIndex) 'The clean exit was not logged after its close request' -AppExited
Assert-That (Test-Path $recordPath) 'The exit wrote no record' -AppExited
$record = (Get-Content $recordPath -Raw).Trim()
$recordPattern = '^at=\d+ version=' + [regex]::Escape($session.expected_version) + ' reason=wm_close uptime=\d+ code=0$'
Assert-That ($record -match $recordPattern) 'The exit record is malformed' -AppExited
$start.Environment['WAZIG_VERIFY_RESTART'] = $session.id
$app = [Diagnostics.Process]::Start($start)
$session.pid = $app.Id
$session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
$session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'session.json')
$null = Wait-Until { $app.Refresh(); if ($app.HasExited) { throw 'The restarted app exited' }; $app.MainWindowHandle -ne [IntPtr]::Zero } 'restarted window' -Harness
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
$startupPattern = '^\d+ startup: previous exit reason=wm_close at=\d+ version=' + [regex]::Escape($session.expected_version) + ' uptime=\d+ code=0$'
$startupLine = Wait-Until {
    $rows = @(Get-Content $logPath | Where-Object { $_ -match $startupPattern })
    if ($rows.Count -ge 1) { $rows[-1] }
} 'restart reports the previous exit'
Assert-That (-not (Test-Path $recordPath)) 'The restart did not consume the reported exit record'
$restartLines = @(Get-Content $logPath)
$startupIndex = -1
for ($index = 0; $index -lt $restartLines.Count; $index++) {
    if ($restartLines[$index] -ceq $startupLine) { $startupIndex = $index }
}
Assert-That ($startupIndex -gt $exitIndex) 'The restart did not report the exit before it happened'
$chats = Wait-Until { (Read-Control $session status).chat_count } 'restarted chats'
Assert-That ($chats -eq 2) 'The restarted app lost its cached chats'
$null = Get-App $session
Save-Screen $session exit-record
@{ old_pid = $oldPid; pid = $session.pid; close_line = $lines[$closeIndex]; exit_line = $lines[$exitIndex]; record = $record; startup_line = $startupLine; consumed = -not (Test-Path $recordPath); chats = $chats } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Evidence 'exit-record.json')
