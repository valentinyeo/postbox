Invoke-WhatsAppHubJourney $session $messages

. "$PSScriptRoot/paste-image.ps1"
$null = Read-Control $session select -Arguments @('fixture-alpha', '--provider', 'slack')
$null = Wait-Until { (Read-Control $session status).selected.id -eq 'fixture-alpha' } 'identity chat selected'
Invoke-PaletteCommand $session 'Compose message'
Send-Keys $session 'Identity fixture'
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' }).Count -eq 4 -and
        (Read-Control $session status).pending_sends -eq 0
} 'identity retry exhaustion' 100
$before = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' })
Assert-That (@($before.body.client_id | Select-Object -Unique).Count -eq 1) 'Automatic retries changed identity'
Assert-That (@($before | Where-Object accepted -eq $true).Count -eq 1) 'Fixture accepted more than once'
$id = $before[0].body.client_id
$old = Get-App $session
Invoke-PaletteCommand $session 'Quit Postbox'
$null = Wait-Until { $old.Refresh(); $old.HasExited } 'identity restart close'
$start.Environment['WAZIG_VERIFY_RESTART'] = $session.id
$app = [Diagnostics.Process]::Start($start)
$session.pid = $app.Id
$session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
$session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'session.json')
$null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'identity restart window'
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
$null = Wait-Until { (Read-Control $session status).chat_count -gt 0 } 'identity restart chats'
$null = Read-Control $session select -Arguments @('fixture-alpha', '--provider', 'slack')
$bubble = Wait-Until {
    (Read-Control $session messages).messages | Where-Object { $_.text -like '*Identity fixture*unconfirmed*' -and $_.bubble[2] -gt $_.bubble[0] }
} 'restored failed bubble'
$afterRestart = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' })
Assert-That ($afterRestart.Count -eq 4 -and (Read-Control $session status).pending_sends -eq 0) 'Restart automatically retried failure'
$textIdleStart = [DateTime]::UtcNow
Start-Sleep -Seconds 45
Assert-That (@(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' }).Count -eq 4 -and (Read-Control $session status).pending_sends -eq 0) 'Idle restart retried failure'
$textClickAt = [DateTime]::UtcNow
$canvas = [IntPtr](Get-Edit (Get-Window $session) '1024').Current.NativeWindowHandle
$point = [VerifyWindow+Point]::new()
$point.X = [int](($bubble.bubble[0] + $bubble.bubble[2]) / 2)
$point.Y = [int](($bubble.bubble[1] + $bubble.bubble[3]) / 2)
Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$point)) 'Failed bubble origin missing'
[VerifyMenus]::Click($session.pid, $point.X, $point.Y, $false)
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' -and $_.status -eq 200 }).Count -eq 1
} 'explicit retry acknowledged'
$after = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' })
Assert-That ($after.Count -eq 5 -and @($after.body.client_id | Select-Object -Unique).Count -eq 1 -and $after[-1].body.client_id -eq $id) 'Explicit retry changed identity'
Assert-That (@($after | Where-Object accepted -eq $true).Count -eq 1) 'Explicit retry duplicated delivery'
$null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'retry completion saved'
@{ idle_start = $textIdleStart.ToString('o'); click = $textClickAt.ToString('o'); before = $afterRestart.Count; after = $after.Count } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'identity-boundary.json')
Invoke-PaletteCommand $session 'Compose message'
Send-Keys $session 'Identity fixture'
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' }).Count -eq 6
} 'separate identical intent'
$both = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' })
Assert-That ($both[-1].body.client_id -ne $id -and $both[-1].accepted -eq $true) 'Separate intent reused identity'
$null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'separate intent acknowledged'
Hub-Pass $session terminal-identity-restart

Invoke-PaletteCommand $session 'Compose message'
$null = [VerifyPasteImage]::Put(80, 60, 'bitmap')
Send-Keys $session '^v'
Send-Keys $session 'Identity file'
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity file' }).Count -eq 4 -and
        (Read-Control $session status).pending_sends -eq 0
} 'file identity retry exhaustion' 100
$files = @(Get-ChildItem $messages -Filter 'hub-*-outbox.jsonl')
Assert-That ($files.Count -eq 1) 'Unified journal missing'
$failed = @(Get-Content $files[0].FullName | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.state -eq 'failed' -and $_.text -eq 'Identity file' })
Assert-That ($failed.Count -eq 1 -and (Test-Path $failed[0].file)) 'Failed file not retained'
$fileId = $failed[0].id
$filePath = $failed[0].file
$null = Wait-Until { @((Read-Control $session messages).messages | Where-Object { $_.id -eq 'identity-collision' }).Count -eq 1 } 'collision history visible'
Assert-That (Test-Path $filePath) 'Caption collision deleted failed file'
$old = Get-App $session
Invoke-PaletteCommand $session 'Quit Postbox'
$null = Wait-Until { $old.Refresh(); $old.HasExited } 'file identity restart close'
$app = [Diagnostics.Process]::Start($start)
$session.pid = $app.Id
$session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
$session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'session.json')
$null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'file identity restart window'
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
$null = Wait-Until { (Read-Control $session status).chat_count -gt 0 } 'file identity restart chats'
$null = Read-Control $session select -Arguments @('fixture-alpha', '--provider', 'slack')
$fileBubble = Wait-Until {
    (Read-Control $session messages).messages | Where-Object { $_.text -like '*Identity file*unconfirmed*' -and $_.bubble[2] -gt $_.bubble[0] }
} 'restored failed file'
Assert-That ((Test-Path $filePath) -and @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity file' }).Count -eq 4 -and (Read-Control $session status).pending_sends -eq 0) 'File restart lost intent or retried'
$fileIdleStart = [DateTime]::UtcNow
Start-Sleep -Seconds 45
Assert-That ((Test-Path $filePath) -and @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity file' }).Count -eq 4 -and (Read-Control $session status).pending_sends -eq 0) 'Idle restart retried file'
$fileClickAt = [DateTime]::UtcNow
$canvas = [IntPtr](Get-Edit (Get-Window $session) '1024').Current.NativeWindowHandle
$point = [VerifyWindow+Point]::new()
$point.X = [int](($fileBubble.bubble[0] + $fileBubble.bubble[2]) / 2)
$point.Y = [int](($fileBubble.bubble[1] + $fileBubble.bubble[3]) / 2)
Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$point)) 'Failed file origin missing'
[VerifyMenus]::Click($session.pid, $point.X, $point.Y, $false)
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity file' -and $_.status -eq 200 }).Count -eq 1 -and
        (Read-Control $session status).pending_sends -eq 0
} 'file retry acknowledged'
$fileSends = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity file' })
Assert-That ($fileSends.Count -eq 5 -and @($fileSends.body.client_id | Select-Object -Unique).Count -eq 1 -and $fileSends[-1].body.client_id -eq $fileId) 'File retry changed identity'
Assert-That (@($fileSends.file_sha256 | Select-Object -Unique).Count -eq 1 -and @($fileSends | Where-Object accepted -eq $true).Count -eq 1) 'File retry changed bytes or duplicated delivery'
@{ idle_start = $fileIdleStart.ToString('o'); click = $fileClickAt.ToString('o'); before = 4; after = $fileSends.Count } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'file-identity-boundary.json')
[Windows.Forms.Clipboard]::Clear()
Hub-Pass $session terminal-file-identity-restart
