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
$requestLog = Join-Path $Evidence 'bridge-requests.jsonl'
$readRequests = { @(Get-Content $requestLog | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.wire_path -like '/v1/wazig/messages*' -and $_.wire_path -match 'limit=80(?:&|$)' }) }
$transientStart = @(& $readRequests).Count
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/message-failures" -Headers $headers -Body '{"count":1}' -ContentType 'application/json' | Out-Null
Invoke-PaletteCommand $session 'Refresh'
$transient = Wait-Until {
    $rows = @(& $readRequests) | Select-Object -Skip $transientStart
    $state = Read-Control $session status
    Assert-That (-not $state.update_card.visible -and $state.update_card.error -ceq '') 'Short message read glitch raised an update error'
    if (@($rows).Count -gt 1 -and @($rows | Where-Object status -eq 503).Count -eq 1 -and @($rows)[-1].status -eq 200) { $state.update_card }
} 'transient message read recovers silently'
$persistentStart = @(& $readRequests).Count
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/message-failures" -Headers $headers -Body '{"count":-1}' -ContentType 'application/json' | Out-Null
Invoke-PaletteCommand $session 'Refresh'
$readProblem = Wait-Until {
    $state = Read-Control $session status
    if ($state.update_card.visible -and $state.update_card.error -ceq 'Check your connection, then Retry.') { $state.update_card }
} 'persistent message read exposes actionable retry'
$persistentEnd = @(& $readRequests).Count
Assert-That (($persistentEnd - $persistentStart) -ge 3) 'Message card appeared before existing retries finished'
Save-Screen $session message-read-problem
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/message-failures" -Headers $headers -Body '{"count":0}' -ContentType 'application/json' | Out-Null
$recoveryStart = @(& $readRequests).Count
Assert-That ((Read-Control $session status).update_card.error -ceq 'Check your connection, then Retry.') 'Message error disappeared before the actual Retry click'
$retryX = [int]($origin.X + $readProblem.rect[0] + 68 * $scale)
$retryY = [int]($origin.Y + $readProblem.rect[3] - 23 * $scale)
[VerifyMenus]::Click($session.pid, $retryX, $retryY, $false)
$readRecovered = Wait-Until {
    $rows = @(& $readRequests) | Select-Object -Skip $recoveryStart
    $state = Read-Control $session status
    if (@($rows | Where-Object status -eq 200).Count -gt 0 -and -not $state.update_card.visible -and $state.update_card.error -ceq '') { $state.update_card }
} 'message retry button refreshes messages and clears its own error'
Save-Screen $session message-read-recovered
@{ transient_start = $transientStart; persistent_start = $persistentStart; persistent_end = $persistentEnd; recovery_start = $recoveryStart; transient = $transient; problem = $readProblem; recovered = $readRecovered; requests = @(& $readRequests); retry = @($retryX, $retryY) } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'message-read-recovery.json')
$compose.SetFocus()
Send-Keys $session 'Recovery draft'
$draftPath = Join-Path $messages 'drafts.json'
$null = Wait-Until { (Read-Edit $compose) -ceq 'Recovery draft' -and (Test-Path $draftPath) -and (Get-Content $draftPath -Raw).Contains('Recovery draft') } 'saved recovery draft'
$originalState = Read-Control $session status
$originalMessages = Read-Control $session messages
Assert-That ($originalState.selected.id -and @($originalMessages.messages).Count -gt 0) 'Selected message baseline missing'
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/sync-failure" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
Invoke-PaletteCommand $session 'Refresh'
$expectedProblem = 'Unable to read chats from wacli'
$problem = Wait-Until {
    Assert-That ([VerifyMenus]::Find($session.pid, '#32770') -eq [IntPtr]::Zero) 'Sync failure opened a modal dialog'
    $state = Read-Control $session status
    if ($state.update_card.visible -and $state.update_card.span -gt 0 -and $state.update_card.error -ceq $expectedProblem) { $state.update_card }
} 'sync failure reaches existing sidebar update card'
$bounds = $list.Current.BoundingRectangle
Assert-That ([Math]::Abs($bounds.Bottom - ($origin.Y + $problem.rect[1] - 4 * $scale)) -le 1) 'Visible card did not reclaim its list clearance'
$requests = @(Get-Content (Join-Path $Evidence 'bridge-requests.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
$failures = @($requests | Where-Object { $_.wire_path -like '/v1/wazig/chats*' -and $_.status -eq 503 })
Assert-That ($failures.Count -gt 0) 'Provider never rejected a real sync read'
Save-Screen $session sync-problem
Send-Keys $session '^k'
$palette = Get-PaletteWindow $session
Send-Keys $session 'version'
$paletteList = Get-Edit $palette '1072'
$null = Wait-Until { (Read-ListCount $paletteList) -eq 1 } 'palette remains usable during sync failure'
Assert-That (@(Read-ListLabels $paletteList)[0] -ceq $expected) 'Sync failure blocked version discovery'
Send-Keys $session '{ESC}'
$retained = (Read-Control $session status).update_card
$dialogHandle = [VerifyMenus]::Find($session.pid, '#32770')
Assert-That ($dialogHandle -eq [IntPtr]::Zero -and $retained.visible -and $retained.error -ceq $expectedProblem) 'Problem did not persist in the existing card after palette dismissal'
@{ surface = 'update_card'; pid = $window.Current.ProcessId; card = $problem; retained = $retained; dialog = $dialogHandle.ToInt64(); expected = $expectedProblem; failures = $failures; list_bottom = $bounds.Bottom; card_top = $origin.Y + $problem.rect[1]; gap = 4 * $scale } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'sync-problem.json')
$null = Wait-Until { @((Get-Content $requestLog | ForEach-Object { $_ | ConvertFrom-Json }) | Where-Object { $_.wire_path -like '/v1/wazig/chats*' -and $_.status -eq 503 }).Count -ge 4 } 'automatic chat retries exhausted'
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/sync-recover" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
Save-Screen $session after
$chatRequests = { @(Get-Content $requestLog | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.wire_path -like '/v1/wazig/chats*' }) }
$manualStart = @(& $chatRequests).Count
$retryX = [int]($origin.X + $problem.rect[0] + 68 * $scale)
$retryY = [int]($origin.Y + $problem.rect[3] - 23 * $scale)
[VerifyMenus]::Click($session.pid, $retryX, $retryY, $false)
$manual = Wait-Until {
    $rows = @(& $chatRequests) | Select-Object -Skip $manualStart
    $state = Read-Control $session status
    if (@($rows | Where-Object status -eq 200).Count -gt 0 -and -not $state.update_card.visible -and $state.update_card.error -ceq '') { $state }
} 'chat Retry fetches chats and clears its own error'
$manualMessages = Read-Control $session messages
Assert-That ($manual.selected.id -ceq $originalState.selected.id -and $manual.chat_count -eq 2 -and @($manualMessages.messages).Count -eq @($originalMessages.messages).Count) 'Retry changed selection or messages'
Assert-That ((Read-Edit $compose) -ceq 'Recovery draft' -and (Get-Content $draftPath -Raw).Contains('Recovery draft')) 'Retry lost saved draft'
$null = Get-App $session
Save-Screen $session chat-read-recovered
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/sync-failure" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
Invoke-PaletteCommand $session 'Refresh'
$automaticProblem = Wait-Until {
    $state = Read-Control $session status
    if ($state.update_card.visible -and $state.update_card.error -ceq $expectedProblem) { $state.update_card }
} 'automatic recovery begins with a chat error'
$autoStart = @(& $chatRequests).Count
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/sync-recover" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
$automatic = Wait-Until {
    $rows = @(& $chatRequests) | Select-Object -Skip $autoStart
    $state = Read-Control $session status
    if (@($rows | Where-Object status -eq 200).Count -gt 0 -and -not $state.update_card.visible -and $state.update_card.error -ceq '') { $state }
} 'scheduled fresh chat read clears its own error'
$automaticMessages = Read-Control $session messages
Assert-That ($automatic.selected.id -ceq $originalState.selected.id -and $automatic.chat_count -eq 2 -and @($automaticMessages.messages).Count -eq @($originalMessages.messages).Count) 'Automatic recovery changed selection or messages'
Assert-That ((Read-Edit $compose) -ceq 'Recovery draft' -and (Get-Content $draftPath -Raw).Contains('Recovery draft')) 'Automatic recovery lost saved draft'
$null = Get-App $session
$launchLog = Get-Content (Join-Path $messages 'launch-log.txt') -Raw
Assert-That (-not $launchLog.Contains('update: card clicked')) 'Chat Retry launched an update'
Save-Screen $session chat-read-auto-recovered
@{ pid = $session.pid; manual_start = $manualStart; auto_start = $autoStart; requests = @(& $chatRequests); initial = $originalState; manual = $manual; automatic_problem = $automaticProblem; automatic = $automatic; original_messages = $originalMessages; manual_messages = $manualMessages; automatic_messages = $automaticMessages; draft = Read-Edit $compose; retry = @($retryX, $retryY) } | ConvertTo-Json -Depth 16 | Set-Content (Join-Path $Evidence 'chat-read-recovery.json')
Copy-Item $draftPath (Join-Path $Evidence 'chat-read-draft.json')
$null = Wait-Until { @(Read-BridgeRequests $session | Where-Object { $_.path -eq '/v1/events' -and $_.last_event_id -eq '1' }).Count -gt 0 } 'event stream resumed'
$orderBefore = Read-Control $session messages
$beforeIds = @($orderBefore.messages | ForEach-Object { $_.id })
Assert-That ($beforeIds.Count -gt 0 -and 'LIVE' -cnotin $beforeIds) 'Ordering baseline is not clean'
$chatsReadBefore = @((Get-Content (Join-Path $messages 'launch-log.txt')) | Where-Object { $_ -match 'chats-read: ok' }).Count
$null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/order-arm" -Headers $headers -Body '{}' -ContentType 'application/json'
try {
    $null = Wait-Until { @(Read-BridgeRequests $session | Where-Object phase -CEQ 'order-chat-held').Count -eq 1 } 'chat response held'
    $orderVisible = Wait-Until {
        $shown = Read-Control $session messages
        if (@($shown.messages | Where-Object id -CEQ 'LIVE').Count -eq 1) { $shown }
    } 'new selected message visible while chats held'
    $visibleIds = @($orderVisible.messages | ForEach-Object { $_.id })
    Assert-That (($visibleIds | ConvertTo-Json -Compress) -ceq (@($beforeIds + 'LIVE') | ConvertTo-Json -Compress)) 'Full ordered history changed'
    Assert-That (@($orderVisible.messages | Where-Object { $_.id -ceq 'LIVE' -and $_.text -ceq 'Fixture live event' }).Count -eq 1) 'Canonical message missing'
    Assert-That ((Read-Control $session status).selected.id -ceq $originalState.selected.id -and (Read-Edit $compose) -ceq 'Recovery draft' -and (Get-Content $draftPath -Raw).Contains('Recovery draft')) 'Selection or saved draft changed'
    $null = Get-App $session
    Save-Screen $session message-before-chat-release
    $mark = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/order-visible" -Headers $headers -Body '{}' -ContentType 'application/json'
    Assert-That $mark.held 'Chat response released before visibility'
    $orderVisible | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'order-visible.messages.json')
} finally {
    $null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/order-release" -Headers $headers -Body '{}' -ContentType 'application/json'
}
$null = Wait-Until { @(Read-BridgeRequests $session | Where-Object { $_.phase -ceq 'order-chat-released' -and $_.manual }).Count -eq 1 } 'chat barrier released'
$null = Wait-Until { @((Get-Content (Join-Path $messages 'launch-log.txt')) | Where-Object { $_ -match 'chats-read: ok' }).Count -gt $chatsReadBefore -and (Read-Control $session status).chat_count -eq 2 -and (Read-Control $session status).selected.id -ceq $originalState.selected.id } 'fresh sidebar and selection preserved'
$orderTrace = @(Read-BridgeRequests $session | Where-Object { $_.phase -in @('order-armed', 'order-history-response', 'order-chat-held', 'order-visible', 'order-chat-released') })
$phases = @($orderTrace | ForEach-Object { $_.phase })
$history = [array]::IndexOf($phases, 'order-history-response')
$held = [array]::IndexOf($phases, 'order-chat-held')
$visible = [array]::IndexOf($phases, 'order-visible')
$released = [array]::IndexOf($phases, 'order-chat-released')
Assert-That ($history -ge 0 -and $history -lt $held -and $held -lt $visible -and $visible -lt $released -and $orderTrace[$history].chat -ceq $originalState.selected.id) 'Provider chronology differs'
@{ pid = $session.pid; before_ids = $beforeIds; visible_ids = $visibleIds; draft = Read-Edit $compose; trace = $orderTrace; selected = (Read-Control $session status).selected.id } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'event-order.json')
Save-Screen $session event-order-after
