Add-Type -Path "$PSScriptRoot/menus.cs"
$window = Get-Window $session
$handle = [IntPtr]$window.Current.NativeWindowHandle
$client = [VerifyWindow+Rect]::new()
$origin = [VerifyWindow+Point]::new()
Assert-That ([VerifyWindow]::GetClientRect($handle, [ref]$client)) 'Cannot measure client'
Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'Cannot locate client'
$list = Get-Edit $window '1016'
Assert-That ((Read-ListCount $list) -eq 2) 'Positive chat-list control failed'
$elements = $window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
$labels = @($elements | ForEach-Object { $_.Current.Name })
$statusControls = @($elements | Where-Object { $_.Current.AutomationId -eq '1048' }).Count
$nativeStatus = [VerifyWindow]::GetDlgItem($handle, 1048)
$forbiddenLabels = @($labels | Where-Object { $_ -match 'You are on v|newest version|[Ss]yncing' })
$bounds = $list.Current.BoundingRectangle
Assert-That ($statusControls -eq 0 -and $nativeStatus -eq [IntPtr]::Zero -and $forbiddenLabels.Count -eq 0) 'Bottom-left status control or label remains'
Assert-That ([Math]::Abs($bounds.Bottom - ($origin.Y + $client.Bottom)) -le 1) 'Status layout slot still consumes chat-list space'
$scale = [VerifyWindow]::GetDpiForWindow($handle) / 96.0
$x = [int]($origin.X + 24 * $scale)
$y = [int]($origin.Y + $client.Bottom - 13 * $scale)
$beforeClick = Read-Control $session status
[VerifyMenus]::Hover($session.pid, $x, $y)
[VerifyMenus]::Click($session.pid, $x, $y, $false)
$clock = [Diagnostics.Stopwatch]::StartNew()
$null = Wait-Until {
    $state = Read-Control $session status
    Assert-That ($state.selected.id -ceq $beforeClick.selected.id -and $state.view -ceq $beforeClick.view -and $state.include_archived -eq $beforeClick.include_archived -and $state.show_archived -eq $beforeClick.show_archived -and $state.pending_sends -eq 0 -and $state.pending_archives -eq 0) 'Former status click changed the app'
    Assert-That ([VerifyMenus]::Find($session.pid, 'MessagesPalette') -eq [IntPtr]::Zero -and [VerifyMenus]::Find($session.pid, '#32770') -eq [IntPtr]::Zero) 'Former status click opened UI'
    $clock.ElapsedMilliseconds -ge 1000
} 'former status click stays inert'
$tooltipHandle = [VerifyMenus]::Find($session.pid, 'tooltips_class32')
$tooltipLabels = @()
if ($tooltipHandle -ne [IntPtr]::Zero) {
    $tooltipLabels = @([Windows.Automation.AutomationElement]::FromHandle($tooltipHandle).Current.Name)
}
Assert-That (@($tooltipLabels | Where-Object { $_ -match 'You are on v|newest version|[Ss]yncing' }).Count -eq 0) 'Removed status tooltip remains'
$afterClick = Read-Control $session status
@{ uia_controls = $statusControls; native_control = $nativeStatus.ToInt64(); forbidden_labels = $forbiddenLabels; labels = $labels; list_rows = Read-ListCount $list; list_bottom = $bounds.Bottom; client_bottom = $origin.Y + $client.Bottom; point = @($x, $y); before = $beforeClick; after = $afterClick; tooltip_labels = $tooltipLabels } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'quiet-status.json')
Save-Screen $session quiet-status
Send-Keys $session '^k'
$palette = Get-PaletteWindow $session
$edit = Get-Edit $palette '1064'
$paletteList = Get-Edit $palette '1072'
Send-Keys $session 'Keyboard shortcuts'
$null = Wait-Until { (Read-Edit $edit) -ceq 'Keyboard shortcuts' -and (Read-ListCount $paletteList) -eq 1 } 'positive palette control'
$positive = @(Read-ListLabels $paletteList)
Assert-That ($positive[0] -ceq 'Keyboard shortcuts') 'Positive palette label unreadable'
Send-Keys $session '^a'
Send-Keys $session 'version'
$expected = "You are on v$($afterClick.version) - this is the newest version"
$null = Wait-Until { (Read-Edit $edit) -ceq 'version' -and (Read-ListCount $paletteList) -eq 1 } 'one version row'
$versionRows = @(Read-ListLabels $paletteList)
@{ query = Read-Edit $edit; expected = $expected; rows = $versionRows; positive = $positive } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'version.json')
Assert-That ($versionRows.Count -eq 1 -and $versionRows[0] -ceq $expected) 'Palette version text differs from the former status line'
Save-Screen $session version
Send-Keys $session '{ENTER}'
Assert-That ([VerifyMenus]::Find($session.pid, 'MessagesPalette') -eq [IntPtr]::Zero) 'Version row did not close palette'
$headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/sync-failure" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
Invoke-PaletteCommand $session 'Refresh'
$dialogHandle = Wait-Until { $found = [VerifyMenus]::Find($session.pid, '#32770'); if ($found -ne [IntPtr]::Zero) { $found } } 'sync failure reaches existing native problem dialog'
$dialog = [Windows.Automation.AutomationElement]::FromHandle($dialogHandle)
$problemLabels = @($dialog.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name })
$expectedProblem = 'Unable to read chats from wacli'
Assert-That ($problemLabels -ccontains $expectedProblem) 'Problem dialog lacks the actual sync-read failure'
$requests = @(Get-Content (Join-Path $Evidence 'bridge-requests.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
$failures = @($requests | Where-Object { $_.wire_path -like '/v1/wazig/chats*' -and $_.status -eq 503 })
Assert-That ($failures.Count -gt 0) 'Provider never rejected a real sync read'
@{ class = $dialog.Current.ClassName; pid = $dialog.Current.ProcessId; labels = $problemLabels; expected = $expectedProblem; failures = $failures } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'sync-problem.json')
Save-Screen $session sync-problem
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/sync-recover" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
$null = [VerifyWindow]::SetForegroundWindow($dialogHandle)
Send-Keys $session '{ENTER}'
Add-Content (Join-Path $Evidence 'actions.log') 'problem: dismissed owned native dialog'
$null = Wait-Until { [VerifyMenus]::Find($session.pid, '#32770') -eq [IntPtr]::Zero } 'problem dismissed through real keyboard input'
Save-Screen $session after
