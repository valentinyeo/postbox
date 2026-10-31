Invoke-WhatsAppHubJourney $session $messages

. "$PSScriptRoot/paste-image.ps1"
. "$PSScriptRoot/hub-picker-proof.ps1"

function Save-IdentityState($Session, [string]$Name) {
    $snapshots = @(Get-ChildItem (Join-Path $messages 'unified-journal-v2') -Filter 'snapshot.v2' -Recurse -File)
    Assert-That ($snapshots.Count -eq 1) 'Expected one unified snapshot'
    Copy-Item $snapshots[0].FullName (Join-Path $Session.evidence "$Name.snapshot.json")
    $status = Read-Control $Session status
    $status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.status.json")
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.messages.json")
    Assert-That ($status.pending_sends -eq 0 -and $status.unified_snapshot.loaded -and $status.unified_snapshot.ready -eq 0 -and $status.unified_snapshot.uncertain -eq 0 -and $status.unified_snapshot.inflight -eq 0 -and $status.unified_snapshot.hub_jobs -eq 0) 'Unified outbox is not idle'
    return Get-Content $snapshots[0].FullName -Raw | ConvertFrom-Json
}

function Select-IdentityReply($Session) {
    $original = Wait-Until {
        (Read-Control $Session messages).messages | Where-Object { $_.id -ceq 'BASELINE' -and $_.bubble[2] -gt $_.bubble[0] }
    } 'identity reply target visible'
    $canvas = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
    $point = [VerifyWindow+Point]::new()
    $point.X = [int](($original.bubble[0] + $original.bubble[2]) / 2)
    $point.Y = [int](($original.bubble[1] + $original.bubble[3]) / 2)
    Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$point)) 'Reply target origin missing'
    [VerifyMenus]::Click($Session.pid, $point.X, $point.Y, $true)
    $menu = Wait-Popup $Session '#32768'
    $client = [VerifyWindow+Rect]::new()
    $origin = [VerifyWindow+Point]::new()
    Assert-That ([VerifyWindow]::GetClientRect($menu, [ref]$client) -and [VerifyWindow]::ClientToScreen($menu, [ref]$origin)) 'Reply menu bounds missing'
    $dpi = [VerifyWindow]::GetDpiForWindow($menu)
    $cell = [int][Math]::Floor((36 * $dpi + 48) / 96)
    $separator = [int][Math]::Floor((8 * $dpi + 48) / 96)
    $row = [int](($client.Bottom - $cell - 3 * $separator) / 4)
    Assert-That ($row -gt 0) 'Reply menu row missing'
    [VerifyMenus]::Click($Session.pid, $origin.X + [int]($client.Right / 2), $origin.Y + [int]($row / 2), $false)
    Add-Content (Join-Path $Session.evidence 'actions.log') 'SendInput: choose measured identity Reply menu row'
    $null = Wait-Until { (Read-Control $Session status).reply.id -ceq 'BASELINE' } 'identity reply selected'
}

function Restart-IdentityApp($Session) {
    $old = Get-App $Session
    Invoke-PaletteCommand $Session 'Quit Postbox'
    $null = Wait-Until { $old.Refresh(); $old.HasExited } 'identity restart close'
    $start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $newApp = [Diagnostics.Process]::Start($start)
    $Session.pid = $newApp.Id
    $Session.startTicks = $newApp.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    $null = Wait-Until { $newApp.Refresh(); $newApp.MainWindowHandle -ne [IntPtr]::Zero } 'identity restart window'
    [VerifyWindow]::ShowWindow($newApp.MainWindowHandle, 3) | Out-Null
    $null = Wait-Until { (Read-Control $Session status).chat_count -gt 0 } 'identity restart chats'
    $null = Read-Control $Session select -Arguments @('fixture-alpha', '--provider', 'slack')
}

function Click-IdentityBubble($Session, $Bubble, [string]$Name, [string]$Label, [string]$Id) {
    $canvas = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
    $point = [VerifyWindow+Point]::new()
    $point.X = [int](($Bubble.bubble[0] + $Bubble.bubble[2]) / 2)
    $point.Y = [int](($Bubble.bubble[1] + $Bubble.bubble[3]) / 2)
    Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$point)) 'Failed bubble origin missing'
    $null = Save-IdentityState $Session "$Name-preclick"
    $requests = @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq $Label })
    $requests | ConvertTo-Json -Depth 12 -AsArray | Set-Content (Join-Path $Session.evidence "$Name-preclick.requests.json")
    Assert-That ($requests.Count -eq 4) 'Retry arrived before manual input'
    Assert-That (-not (Test-Path (Join-Path $messages "verification-retry-$Id-5.json"))) 'Retry marker appeared before manual input'
    Assert-That (-not (Test-Path (Join-Path $messages "verification-dispatch-$Id-5.json"))) 'Retry dispatched before manual input'
    [VerifyMenus]::Click($Session.pid, $point.X, $point.Y, $false)
    Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: explicit identity retry x=$($point.X) y=$($point.Y)"
}

$null = Read-Control $session select -Arguments @('fixture-alpha', '--provider', 'slack')
$null = Wait-Until { (Read-Control $session status).selected.id -eq 'fixture-alpha' } 'identity chat selected'
Select-IdentityReply $session
$textSource = Read-Control $session status
$textSource | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'identity-source.json')
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'identity-source.messages.json')
Send-Keys $session 'Identity fixture'
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    $state = Read-Control $session status
    @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' }).Count -eq 4 -and
        $state.pending_sends -eq 0 -and $state.unified_snapshot.loaded -and $state.unified_snapshot.ready -eq 0 -and $state.unified_snapshot.uncertain -eq 0 -and $state.unified_snapshot.inflight -eq 0 -and $state.unified_snapshot.hub_jobs -eq 0 -and $state.unified_snapshot.held -ge 1
} 'identity retry exhaustion' 100
$before = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' })
Assert-That (@($before.body.client_id | Select-Object -Unique).Count -eq 1) 'Automatic retries changed identity'
Assert-That (@($before | Where-Object accepted -eq $true).Count -eq 1) 'Fixture accepted more than once'
$id = $before[0].body.client_id
$held = Save-IdentityState $session 'identity-held'
Assert-That (@($held.records | Where-Object { $_.id -ceq $id -and $_.phase -ceq 'held' }).Count -eq 1) 'Text intent not held'
Restart-IdentityApp $session
$bubble = Wait-Until {
    (Read-Control $session messages).messages | Where-Object { $_.time -ceq $id -and $_.text -like '*Identity fixture*unconfirmed*' -and $_.bubble[2] -gt $_.bubble[0] }
} 'restored failed bubble'
$null = Save-IdentityState $session 'identity-restart'
Save-Screen $session identity-restart
$afterRestart = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' })
$afterRestart | ConvertTo-Json -Depth 12 -AsArray | Set-Content (Join-Path $session.evidence 'identity-restart.requests.json')
Assert-That ($afterRestart.Count -eq 4) 'Restart automatically retried failure'
$textIdleStart = [DateTime]::UtcNow
Start-Sleep -Seconds 45
$null = Save-IdentityState $session 'identity-idle'
$textIdleRequests = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' })
$textIdleRequests | ConvertTo-Json -Depth 12 -AsArray | Set-Content (Join-Path $session.evidence 'identity-idle.requests.json')
Assert-That ($textIdleRequests.Count -eq 4) 'Idle restart retried failure'
$textClickAt = [DateTime]::UtcNow
Click-IdentityBubble $session $bubble identity 'Identity fixture' $id
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' -and $_.status -eq 200 }).Count -eq 1 -and
        (Read-Control $session status).unified_snapshot.inflight -eq 0
} 'explicit retry acknowledged'
$after = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' })
Assert-That ($after.Count -eq 5 -and @($after.body.client_id | Select-Object -Unique).Count -eq 1 -and $after[-1].body.client_id -eq $id) 'Explicit retry changed identity'
Assert-That (@($after | Where-Object accepted -eq $true).Count -eq 1) 'Explicit retry duplicated delivery'
$null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'retry completion saved'
@{ idle_start = $textIdleStart.ToString('o'); click = $textClickAt.ToString('o'); before = $afterRestart.Count; after = $after.Count } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'identity-boundary.json')
Select-IdentityReply $session
$secondSource = Read-Control $session status
$secondSource | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'identity-second-source.json')
Send-Keys $session 'Identity fixture'
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' }).Count -eq 6
} 'separate identical intent'
$both = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity fixture' })
Assert-That ($both[-1].body.client_id -ne $id -and $both[-1].accepted -eq $true) 'Separate intent reused identity'
$null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 -and (Read-Control $session status).unified_snapshot.inflight -eq 0 } 'separate intent acknowledged'
Hub-Pass $session terminal-identity-restart

Invoke-PaletteCommand $session 'Compose message'
$fileSource = Read-Control $session status
$fileSource | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'file-identity-source.json')
$fixture = Join-Path (Join-Path $session.root 'profile') 'identity-image.png'
[VerifyPasteImage]::Fixture($fixture)
Copy-Item $fixture (Join-Path $session.evidence 'identity-original.png')
$fixtureHash = (Get-FileHash $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
@{ filename = [IO.Path]::GetFileName($fixture); sha256 = $fixtureHash } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'picker-fixture.json')
Send-Keys $session 'Identity file'
$draft = Read-Edit (Get-Edit (Get-Window $session) '1032')
Assert-That ($draft -ceq 'Identity file') 'picker: synthetic draft missing'
Add-HubPickerImage $session $fixture
$null = Wait-Until { (Read-Control $session status).staged_attachment_count -eq 1 } 'identity picker staged image'
Assert-That ((Read-Edit (Get-Edit (Get-Window $session) '1032')) -ceq $draft) 'picker: synthetic draft changed'
Save-Screen $session picker-staged
$canvas = (Get-Edit (Get-Window $session) '1024').Current.BoundingRectangle
$compose = (Get-Edit (Get-Window $session) '1032').Current.BoundingRectangle
$screen = [Windows.Forms.SystemInformation]::VirtualScreen
$preview = [VerifyPasteImage]::Preview((Join-Path $session.evidence 'picker-staged.png'), [int]($canvas.Left - $screen.Left), [int]($canvas.Bottom - $screen.Top), [int]($canvas.Right - $screen.Left), [int]($compose.Top - $screen.Top), $true)
@{ draft_before = $draft; draft_after = (Read-Edit (Get-Edit (Get-Window $session) '1032')); preview = $preview } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'picker-staged.json')
Invoke-PaletteCommand $session 'Compose message'
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    $state = Read-Control $session status
    @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity file' }).Count -eq 4 -and
        $state.pending_sends -eq 0 -and $state.unified_snapshot.loaded -and $state.unified_snapshot.ready -eq 0 -and $state.unified_snapshot.uncertain -eq 0 -and $state.unified_snapshot.inflight -eq 0 -and $state.unified_snapshot.hub_jobs -eq 0 -and $state.unified_snapshot.held -ge 1
} 'file identity retry exhaustion' 100
$failedSnapshot = Save-IdentityState $session 'file-identity-held'
$failed = @($failedSnapshot.records | Where-Object { $_.phase -ceq 'held' -and $_.text -ceq 'Identity file' })
Assert-That ($failed.Count -eq 1 -and $failed[0].attachment_ready -and (Test-Path $failed[0].owned_file)) 'Failed file not retained'
$fileId = $failed[0].id
$filePath = $failed[0].owned_file
Copy-Item $filePath (Join-Path $session.evidence 'identity-held.payload')
$null = Wait-Until { @((Read-Control $session messages).messages | Where-Object { $_.id -eq 'identity-collision' }).Count -eq 1 } 'collision history visible'
Assert-That (Test-Path $filePath) 'Caption collision deleted failed file'
$null = Save-IdentityState $session 'file-identity-collision'
Restart-IdentityApp $session
$fileBubble = Wait-Until {
    (Read-Control $session messages).messages | Where-Object { $_.time -ceq $fileId -and $_.text -like '*Identity file*unconfirmed*' -and $_.bubble[2] -gt $_.bubble[0] }
} 'restored failed file'
$null = Save-IdentityState $session 'file-identity-restart'
Save-Screen $session file-identity-restart
$fileRestartRequests = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity file' })
$fileRestartRequests | ConvertTo-Json -Depth 12 -AsArray | Set-Content (Join-Path $session.evidence 'file-identity-restart.requests.json')
Assert-That ((Test-Path $filePath) -and $fileRestartRequests.Count -eq 4) 'File restart lost intent or retried'
$fileIdleStart = [DateTime]::UtcNow
Start-Sleep -Seconds 45
$null = Save-IdentityState $session 'file-identity-idle'
$fileIdleRequests = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity file' })
$fileIdleRequests | ConvertTo-Json -Depth 12 -AsArray | Set-Content (Join-Path $session.evidence 'file-identity-idle.requests.json')
Assert-That ((Test-Path $filePath) -and $fileIdleRequests.Count -eq 4) 'Idle restart retried file'
$fileClickAt = [DateTime]::UtcNow
Click-IdentityBubble $session $fileBubble file-identity 'Identity file' $fileId
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity file' -and $_.status -eq 200 }).Count -eq 1 -and
        (Read-Control $session status).pending_sends -eq 0 -and (Read-Control $session status).unified_snapshot.inflight -eq 0
} 'file retry acknowledged'
$fileSends = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -eq 'Identity file' })
Assert-That ($fileSends.Count -eq 5 -and @($fileSends.body.client_id | Select-Object -Unique).Count -eq 1 -and $fileSends[-1].body.client_id -eq $fileId) 'File retry changed identity'
Assert-That (@($fileSends.file_sha256 | Select-Object -Unique).Count -eq 1 -and @($fileSends | Where-Object accepted -eq $true).Count -eq 1) 'File retry changed bytes or duplicated delivery'
Assert-That ($fileSends[0].file_sha256 -ceq $fixtureHash -and $fileSends[0].body.file -ceq [IO.Path]::GetFileName($fixture) -and $fileSends[0].body.chat -ceq 'fixture-alpha') 'picker: fixture upload differs from original'
@{ idle_start = $fileIdleStart.ToString('o'); click = $fileClickAt.ToString('o'); before = 4; after = $fileSends.Count } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'file-identity-boundary.json')
Hub-Pass $session terminal-file-identity-restart
