. "$PSScriptRoot/menus.ps1"

function Click-ReplyRect($Session, $Handle, $Rect, [bool]$Right = $false) {
    $point = [VerifyWindow+Point]::new()
    $point.X = [int](($Rect[0] + $Rect[2]) / 2)
    $point.Y = [int](($Rect[1] + $Rect[3]) / 2)
    Assert-That ([VerifyWindow]::ClientToScreen($Handle, [ref]$point)) 'Reply click origin missing'
    [VerifyMenus]::Click($Session.pid, $point.X, $point.Y, $Right)
    Add-Content (Join-Path $Session.evidence 'actions.log') "Reply SendInput right=$Right x=$($point.X) y=$($point.Y)"
}

Send-Keys $session '^1'
foreach ($target in @(
    @{ provider = 'whatsapp'; chat = 'fixture-beta'; search = 'Verification Beta' },
    @{ provider = 'slack'; chat = 'fixture-alpha'; search = 'Verification Alpha' }
)) {
    $name = $target.provider
    Send-Keys $session '^f'
    Send-Keys $session $target.search
    $null = Wait-Until {
        $state = Read-Control $session status
        $state.selected.id -eq $target.chat -and $state.selected.provider -eq $name -and
            @((Read-Control $session messages).messages | Where-Object id -CEQ 'REPLY-ORIGINAL').Count -eq 1
    } "$name original shown"
    Click-Control $session '1032'
    $canvas = [IntPtr](Get-Edit (Get-Window $session) '1024').Current.NativeWindowHandle
    $window = [IntPtr](Get-Window $session).Current.NativeWindowHandle
    $original = Wait-Until {
        (Read-Control $session messages).messages | Where-Object { $_.id -ceq 'REPLY-ORIGINAL' -and $_.bubble[2] -gt $_.bubble[0] }
    } "$name original painted"
    Save-Screen $session "$name-before"
    Click-ReplyRect $session $canvas $original.bubble $true
    $null = Wait-Popup $session '#32768'
    Send-Keys $session '{HOME}{ENTER}'
    $state = Read-Control $session status
    Assert-That ($state.reply.id -ceq 'REPLY-ORIGINAL') 'Reply preview missing'
    Assert-That ($state.reply.sender -ceq 'Fixture Sender') 'Reply sender missing'
    Assert-That ($state.reply.preview -ceq 'First words of the original') 'Reply preview must use first line'
    Assert-That ($state.reply.bar[0] -eq $state.composer.box.left -and $state.reply.bar[2] -eq $state.composer.box.right) 'Reply and composer edges differ'
    Assert-That ($state.reply.bar[3] -lt $state.composer.box.top) 'Reply bar covers composer'
    $canvasRect = [VerifyWindow+Rect]::new()
    Assert-That ([VerifyWindow]::GetClientRect($canvas, [ref]$canvasRect)) 'Canvas bounds missing'
    Assert-That ($canvasRect.Bottom -le $state.reply.bar[1]) 'Reply bar overlaps messages'
    Save-Screen $session "$name-replying"
    Click-ReplyRect $session $window $state.reply.close
    $null = Wait-Until { (Read-Control $session status).reply.id -ceq '' } "$name close cancels reply"
    Invoke-PaletteCommand $session 'Reply to selected message'
    Send-Keys $session '{ESC}'
    $null = Wait-Until { (Read-Control $session status).reply.id -ceq '' } "$name Escape cancels reply"
    Invoke-PaletteCommand $session 'Reply to selected message'
    Send-Keys $session "Synthetic $name reply"
    Send-Keys $session '{ENTER}'
    $null = Wait-Until {
        $requests = Read-BridgeRequests $session
        @($requests | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.status -eq 200 -and $_.body.chat -ceq $target.chat -and $_.body.reply_to -ceq 'REPLY-ORIGINAL' }).Count -eq 1 -and
            (Read-Control $session status).pending_sends -eq 0
    } "$name reply accepted by hub"
    $null = Wait-Until { (Read-Control $session status).reply.id -ceq '' } "$name send clears preview"
    $sent = Wait-Until {
        (Read-Control $session messages).messages | Where-Object { $_.from_me -and $_.quoted_msg_id -ceq 'REPLY-ORIGINAL' -and $_.quote_line[2] -gt $_.quote_line[0] }
    } "$name quoted reply visible"
    Assert-That ($sent.quote_line[3] -lt $sent.bubble[1]) 'Reply quote must sit above the bubble'
    Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence "$name-sent.messages.json")
    Save-Screen $session "$name-sent"
    Click-ReplyRect $session $canvas $sent.quote_line
    $null = Wait-Until { (Read-Control $session status).reply_flash -ceq 'REPLY-ORIGINAL' } "$name original flashes"
    Save-Screen $session "$name-jumped"
    $null = Wait-Until { (Read-Control $session status).reply_flash -ceq '' } "$name highlight fades"
    $orphan = Wait-Until {
        (Read-Control $session messages).messages | Where-Object { $_.id -ceq 'REPLY-ORPHAN' -and $_.quote_line[2] -gt $_.quote_line[0] }
    } "$name unloaded quote painted"
    Click-ReplyRect $session $canvas $orphan.quote_line
    $null = Wait-Until { (Read-Control $session status).reply_notice } "$name missing original notice visible"
    Save-Screen $session "$name-unavailable"
    $null = Wait-Until { -not (Read-Control $session status).reply_notice } "$name notice dismisses"
    Hub-Pass $session "$name-reply-preview-cancel-send-jump"
    Send-Keys $session '^f'
    Send-Keys $session '^a{BACKSPACE}{ESC}'
}
