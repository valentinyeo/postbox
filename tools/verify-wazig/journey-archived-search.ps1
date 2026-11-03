. "$PSScriptRoot/menus.ps1"

$null = Wait-Until { try { (Read-Control $session status).chat_count -ge 1 } catch { $false } } 'fixture inbox loaded before the fresh start' 60

$old = Get-App $session
$oldPid = $session.pid
$oldTicks = $session.startTicks
Invoke-PaletteCommand $session 'Quit Postbox'
$null = Wait-Until { $old.Refresh(); $old.HasExited } 'close for a fresh app start'
$start.Environment['WAZIG_VERIFY_RESTART'] = $session.id
$app = [Diagnostics.Process]::Start($start)
$session.pid = $app.Id
$session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
$session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'session.json')
@{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $session.pid; new_start = $session.startTicks; root = $session.root; id = $session.id; sha256 = $session.sha256 } |
    ConvertTo-Json | Set-Content (Join-Path $session.evidence 'restart.json')
$null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'fresh start window'
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
$null = Wait-Until { try { (Read-Control $session status).chat_count -ge 1 } catch { $false } } 'inbox shown after the fresh start' 60

$name = 'Archived Person Alpha'
$expected = "$name  $([char]0xB7)  Archived"
Send-Keys $session '^f'
$palette = Get-PaletteWindow $session
$edit = Get-Edit $palette '1064'
$list = Get-Edit $palette '1072'
Send-Keys $session $name
$null = Wait-Until { (Read-Edit $edit) -ceq $name } 'first search query typed'
$deadline = [DateTime]::UtcNow.AddSeconds(8)
$labels = [string[]]@()
do {
    try { $labels = [string[]]@(Read-ListLabels $list | ForEach-Object { [string]$_ }) } catch { }
    if ($labels -ccontains $expected) { break }
    [System.Threading.Thread]::Sleep(250)
} while ([DateTime]::UtcNow -lt $deadline)
$age = ([DateTime]::UtcNow - $app.StartTime.ToUniversalTime()).TotalSeconds
Save-Screen $session first-search
[ordered]@{ query = $name; expected = $expected; found = ($labels -ccontains $expected); labels = $labels; seconds_since_start = [Math]::Round($age, 1) } |
    ConvertTo-Json -Depth 6 | Set-Content (Join-Path $session.evidence 'first-search.json')
Assert-That ($labels -ccontains $expected) "the first search after a fresh start has no archived row '$expected', $([Math]::Round($age, 1)) s after start; rows: $(($labels | Select-Object -First 10) -join ' | ')"
Send-Keys $session '{ESC}'
Hub-Pass $session first-search-archived
