function Save-TelegramMessages($Session, [string]$Name) {
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.messages.json")
    Save-Screen $Session $Name
}

function Save-TelegramArchiveObservation($Session, [string]$Phase) {
    $window = Get-Window $Session
    $compose = Get-Edit $window '1032'
    $composeHandle = [IntPtr]$compose.Current.NativeWindowHandle
    $text = Read-Edit $compose
    $state = Read-Control $Session status
    $foregroundHandle = [VerifyWindow]::GetForegroundWindow()
    $foregroundPid = [uint32]0
    if ($foregroundHandle -ne [IntPtr]::Zero) {
        $null = [VerifyWindow]::GetWindowThreadProcessId($foregroundHandle, [ref]$foregroundPid)
    }
    $windowPid = [uint32]0
    $thread = [VerifyWindow]::GetWindowThreadProcessId([IntPtr]$window.Current.NativeWindowHandle, [ref]$windowPid)
    $info = [VerifyWindow+GuiThreadInfo]::new()
    $info.Size = [Runtime.InteropServices.Marshal]::SizeOf([type][VerifyWindow+GuiThreadInfo])
    $threadOk = [VerifyWindow]::GetGUIThreadInfo($thread, [ref]$info)
    $focusedHandle = if ($threadOk) { $info.Focus } else { [IntPtr]::Zero }
    $focused = if ($focusedHandle -ne [IntPtr]::Zero) { [Windows.Automation.AutomationElement]::FromHandle($focusedHandle) } else { $null }
    $focusedPid = 0
    $nativePid = [uint32]0
    $focusedClass = ''
    $focusedId = ''
    $focusedText = $null
    if ($focusedHandle -ne [IntPtr]::Zero) {
        $null = [VerifyWindow]::GetWindowThreadProcessId($focusedHandle, [ref]$nativePid)
    }
    if ($null -ne $focused) {
        $focusedPid = $focused.Current.ProcessId
        $focusedClass = $focused.Current.ClassName
        $focusedId = $focused.Current.AutomationId
        if ($nativePid -eq $Session.pid -and $focusedClass -in @('RICHEDIT50W', 'Edit')) {
            $focusedText = Read-EditText $focusedHandle
        }
    }
    $observation = [ordered]@{
        phase = $Phase
        foreground_hwnd = $foregroundHandle.ToInt64()
        foreground_process_id = $foregroundPid
        gui_thread_ok = $threadOk
        gui_thread_id = $thread
        focused_hwnd = $focusedHandle.ToInt64()
        focused_process_id = $focusedPid
        focused_native_process_id = $nativePid
        focused_class = $focusedClass
        focused_automation_id = $focusedId
        focused_text = $focusedText
        composer_hwnd = $composeHandle.ToInt64()
        composer_process_id = $compose.Current.ProcessId
        composer_class = $compose.Current.ClassName
        composer_automation_id = $compose.Current.AutomationId
        composer_text = $text
        selected = $state.selected
        bulk_selected_count = $state.bulk_selected_count
    }
    $observation | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "telegram-archive-$Phase.json")
    Assert-That ($foregroundHandle -ne [IntPtr]::Zero -and $foregroundPid -eq $Session.pid -and $threadOk -and $thread -ne 0 -and $windowPid -eq $Session.pid -and $focusedHandle -ne [IntPtr]::Zero -and $focusedPid -eq $Session.pid -and $nativePid -eq $Session.pid) "Telegram $Phase focus is not owned by Postbox"
    Assert-That ($composeHandle -ne [IntPtr]::Zero -and $compose.Current.ProcessId -eq $Session.pid -and $compose.Current.ClassName -eq 'RICHEDIT50W' -and $compose.Current.AutomationId -eq '1032') "Telegram $Phase composer identity changed"
    return $observation
}

function Save-TelegramAvatars($Session) {
    $window = Get-Window $Session
    $list = Get-Edit $window '1016'
    $handle = [IntPtr]$list.Current.NativeWindowHandle
    $client = [VerifyWindow+Rect]::new()
    $origin = [VerifyWindow+Point]::new()
    Assert-That ([VerifyWindow]::GetClientRect($handle, [ref]$client)) 'Cannot read Telegram list bounds'
    Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'Cannot read Telegram list origin'
    $rowHeight = [UIntPtr]::Zero
    $topIndex = [UIntPtr]::Zero
    Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x01A1, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$rowHeight) -ne [IntPtr]::Zero) 'Cannot read Telegram row height'
    Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x018E, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$topIndex) -ne [IntPtr]::Zero) 'Cannot read Telegram scroll position'
    Assert-That ($topIndex.ToUInt64() -eq 0) 'Telegram avatar list is scrolled'
    $desktop = [Windows.Forms.SystemInformation]::VirtualScreen
    @{
        dpi = [VerifyWindow]::GetDpiForWindow($handle); row_height = $rowHeight.ToUInt64(); top_index = $topIndex.ToUInt64()
        ids = @((Read-Control $Session chats).chats.id)
        list_x = $origin.X - $desktop.Left; list_y = $origin.Y - $desktop.Top
        client_width = $client.Right; client_height = $client.Bottom
    } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Session.evidence 'telegram-avatars-layout.json')
    $null = Wait-Until {
        Save-Screen $Session linked
        & python "$PSScriptRoot/check-telegram-evidence.py" $Session.evidence --capture | Out-Host
        $LASTEXITCODE -eq 0
    } 'Telegram contact and group photos and no-photo letter circles'
}

function Invoke-TelegramJourney($Session, [string]$Messages) {
    $null = Wait-Until { @((Read-Control $Session status).view_order | Where-Object provider -eq 'telegram').Count -eq 1 } 'Telegram view registered'
    $order = (Read-Control $Session status).view_order
    $number = 1
    while ($order[$number - 1].provider -ne 'telegram') { $number++ }
    Send-Keys $Session "^$($number + 1)"
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.view -eq 'telegram' -and $state.current_view.account -eq 'telegram' -and $state.current_view.label -eq 'Telegram' -and $state.chat_count -eq 5
    } 'Telegram hub chats loaded'
    $rows = (Read-Control $Session chats).chats
    Assert-That (@($rows | Where-Object { $_.provider -ne 'telegram' -or $_.view_account -ne 'telegram' }).Count -eq 0) 'Telegram view includes another account'
    Assert-That (@($rows | Where-Object { $_.id -eq 'telegram:user:9001' -and $_.saved -and $_.name -eq 'Saved Messages' }).Count -eq 1) 'Saved Messages flag missing'
    Send-Keys $Session '^k'
    $palette = Get-PaletteWindow $Session
    $list = Get-Edit $palette '1072'
    $labels = @(Read-ListLabels $list)
    Assert-That ($labels -contains 'Show Telegram') 'Positive Telegram palette control missing'
    Assert-That (@($labels | Where-Object { $_ -match 'Connect Telegram account|Log out of Telegram|Remove Telegram account' }).Count -eq 0) 'Direct Telegram login exposed with hub'
    $labels | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'palette.json')
    Send-Keys $Session '{ESC}'
    $avatarIds = @('telegram:user:1001', 'telegram:user:1002', 'telegram:user:9001', 'telegram:chat:2001', 'telegram:channel:3001')
    foreach ($id in $avatarIds) {
        $encoded = [Uri]::EscapeDataString($id)
        $reply = Invoke-WebRequest -Uri "$($Session.bridge_url)/v1/wazig/avatar/$encoded" -SkipHttpErrorCheck
        Assert-That ($reply.StatusCode -eq 401) 'Telegram avatar route allowed unauthenticated access'
    }
    $null = Wait-Until {
        $requests = Read-BridgeRequests $Session
        foreach ($id in $avatarIds) {
            $route = '/v1/wazig/avatar/' + [Uri]::EscapeDataString($id)
            $fetched = @($requests | Where-Object { $_.authorized -and $_.path -ceq $route })
            $expected = if ($id -in @('telegram:user:1001', 'telegram:chat:2001')) { 200 } else { 404 }
            if ($fetched.Count -ne 1 -or $fetched[0].status -ne $expected) { return $false }
        }
        return $true
    } 'Telegram avatars fetched once per chat'
    Save-TelegramAvatars $Session
    Hub-Pass $Session avatars
    $sidebar = (Get-Edit (Get-Window $Session) '1016').Current.BoundingRectangle
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $image = [Drawing.Bitmap]::new((Join-Path $Session.evidence 'linked.png'))
    $blue = 0
    try {
        for ($y = [int]$sidebar.Top; $y -lt [int][Math]::Min($sidebar.Bottom, $sidebar.Top + 400); $y++) {
            for ($x = [int]$sidebar.Left; $x -lt [int][Math]::Min($sidebar.Right, $sidebar.Left + 100); $x++) {
                $pixel = $image.GetPixel($x - $screen.Left, $y - $screen.Top)
                if ($pixel.R -eq 42 -and $pixel.G -eq 171 -and $pixel.B -eq 238) { $blue++ }
            }
        }
    } finally { $image.Dispose() }
    Assert-That ($blue -gt 20) 'Telegram blue row marks are not painted'
    @{ brand_blue_pixels = $blue } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'marks.json')
    Hub-Pass $Session linked-chats
    Invoke-PaletteCommand $Session 'Verification Telegram'
    $null = Wait-Until { $shown = Read-Control $Session messages; $shown.chat.id -eq 'telegram:user:1001' -and @($shown.messages | Where-Object id -eq '1000').Count -eq 1 } 'Telegram history'
    Save-TelegramMessages $Session history
    Assert-That (@(Read-BridgeRequests $Session | Where-Object { $_.path.StartsWith('/v1/wazig/messages?') -and $_.path.Contains('telegram%3Auser%3A1001') -and $_.status -eq 200 }).Count -gt 0) 'Telegram history bypassed the hub'
    Hub-Pass $Session history
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/mark-read' -and $_.body.chat -eq 'telegram:user:1001' -and $_.body.message_id -match '^100[01]$' -and $_.status -eq 200 }).Count -gt 0 } 'Telegram read receipt'
    $null = Wait-Until { @((Read-Control $Session chats).chats | Where-Object { $_.id -eq 'telegram:user:1001' -and -not $_.unread }).Count -eq 1 } 'Telegram unread cleared'
    Save-Screen $Session read
    Hub-Pass $Session mark-read
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path.StartsWith('/v1/wazig/media/') -and $_.status -eq 200 }).Count -gt 0 } 'Telegram automatic media download'
    $null = Wait-Until { @(Get-ChildItem (Join-Path $Messages 'hub-media') -Filter '*.bin' | Where-Object Length -gt 0).Count -gt 0 } 'Telegram media cached'
    Hub-Pass $Session media
    Send-Keys $Session '%k'
    Invoke-PaletteCommand $Session 'Like'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/react' -and $_.body.chat -eq 'telegram:user:1001' -and $_.body.msg -eq '1001' -and $_.status -eq 200 }).Count -eq 1 } 'Telegram reaction acknowledged'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object { $_.id -eq '1001' -and $_.reaction -eq ([char]::ConvertFromUtf32(0x1f44d)) }).Count -eq 1 } 'Telegram reaction visible'
    Save-TelegramMessages $Session reacted
    Hub-Pass $Session react
    Invoke-PaletteCommand $Session 'Reply to selected message'
    Send-Keys $Session 'Synthetic Telegram reply'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.body.text -eq 'Synthetic Telegram reply' -and $_.body.reply_to -eq '1001' -and $_.accepted }).Count -eq 1 -and (Read-Control $Session status).pending_sends -eq 0 } 'Telegram reply accepted'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object text -eq 'Synthetic Telegram reply').Count -eq 1 } 'Telegram reply visible'
    Save-TelegramMessages $Session reply
    Hub-Pass $Session reply
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session 'Synthetic Telegram outgoing'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.body.text -eq 'Synthetic Telegram outgoing' -and $_.accepted -and -not $_.multipart }).Count -eq 1 -and (Read-Control $Session status).pending_sends -eq 0 } 'Telegram text accepted'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object text -eq 'Synthetic Telegram outgoing').Count -eq 1 } 'Telegram text visible'
    Save-TelegramMessages $Session text
    Hub-Pass $Session send-text
    $file = Join-Path $Session.root 'fixture.png'
    $image = [Drawing.Bitmap]::new(32, 32)
    try { $image.Save($file, [Drawing.Imaging.ImageFormat]::Png) } finally { $image.Dispose() }
    @{ sha256 = (Get-FileHash $file).Hash.ToLowerInvariant(); size = (Get-Item $file).Length } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'file.json')
    New-Item (Join-Path $Session.root 'profile\Desktop') -ItemType Directory -Force | Out-Null
    Invoke-PaletteCommand $Session 'Attach photo or file'
    $picker = Wait-Until {
        Get-AttachmentPicker $Session
    } 'owned attachment picker'
    $controls = Wait-Until {
        $combo = [VerifyWindow]::GetDlgItem($picker, 1148)
        if ($combo -eq [IntPtr]::Zero) { return $false }
        $filename = [VerifyWindow]::FindWindowEx($combo, [IntPtr]::Zero, 'Edit', $null)
        if ($filename -eq [IntPtr]::Zero) {
            $inner = [VerifyWindow]::FindWindowEx($combo, [IntPtr]::Zero, 'ComboBox', $null)
            if ($inner -ne [IntPtr]::Zero) { $filename = [VerifyWindow]::FindWindowEx($inner, [IntPtr]::Zero, 'Edit', $null) }
        }
        $open = [VerifyWindow]::GetDlgItem($picker, 1)
        foreach ($handle in @($picker, $combo, $filename, $open)) {
            if ($handle -eq [IntPtr]::Zero -or -not [VerifyWindow]::IsWindowEnabled($handle)) { return $false }
            $ownerPid = [uint32]0
            $null = [VerifyWindow]::GetWindowThreadProcessId($handle, [ref]$ownerPid)
            Assert-That ($ownerPid -eq $Session.pid) 'Attachment control belongs to another process'
        }
        return @{ filename = $filename; open = $open }
    } 'enabled attachment filename edit and Open button'
    $result = [UIntPtr]::Zero
    $ok = [VerifyWindow]::WriteText($controls.filename, 0x000C, [UIntPtr]::Zero, $file, 2, 2000, [ref]$result)
    Assert-That ($ok -ne [IntPtr]::Zero -and $result -ne [UIntPtr]::Zero) 'Attachment WM_SETTEXT failed'
    Assert-That ((Read-EditText $controls.filename) -ceq $file) 'Attachment filename was not set'
    $ok = [VerifyWindow]::ReadCount($controls.open, 0x00F5, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$result)
    Assert-That ($ok -ne [IntPtr]::Zero) 'Attachment BM_CLICK timed out'
    Add-Content (Join-Path $Session.evidence 'actions.log') 'win32: attachment filename set and verified; Open clicked'
    $null = Wait-Until { [VerifyWindow]::GetForegroundWindow() -eq (Get-App $Session).MainWindowHandle } 'attachment picker closed'
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session 'Synthetic Telegram file'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.multipart -and $_.accepted -and $_.body.chat -eq 'telegram:user:1001' -and $_.file_sha256 -eq (Get-FileHash $file).Hash.ToLowerInvariant() }).Count -eq 1 -and (Read-Control $Session status).pending_sends -eq 0 } 'Telegram multipart bytes accepted'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object { $_.text -eq 'Synthetic Telegram file' -and $_.media_type -eq 'image' }).Count -eq 1 } 'Telegram file visible'
    Save-TelegramMessages $Session file
    Hub-Pass $Session send-file
    Invoke-RestMethod "$($Session.bridge_url)/fixture/live" -Method Post -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' | Out-Null
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object id -eq '1002').Count -eq 1 } 'Telegram live event visible'
    Save-TelegramMessages $Session live
    Hub-Pass $Session live-events
    $failure = @{ chat = 'Verification Limited'; id = 'telegram:user:1002'; reason = 'telegram rate limited'; code = 429; name = 'limited' }
    Invoke-PaletteCommand $Session $failure.chat
    $null = Wait-Until { $shown = Read-Control $Session messages; $shown.chat.id -eq $failure.id -and $shown.messages.Count -gt 0 } 'Telegram rejection chat open'
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session 'Synthetic rejected send'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object { $_.send_state -eq 'failed' -and $_.text.Contains($failure.reason) }).Count -eq 1 -and (Read-Control $Session status).pending_sends -eq 0 } 'Telegram failure reason visible without retry'
    Save-TelegramMessages $Session $failure.name
    Assert-That (@(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.body.chat -eq $failure.id -and $_.status -eq $failure.code }).Count -eq 1) 'Telegram rejection was retried or hidden'
    Hub-Pass $Session limited
    $beforeClear = Save-TelegramArchiveObservation $Session 'before-clear'
    Assert-That ($beforeClear.focused_hwnd -eq $beforeClear.composer_hwnd -and $beforeClear.focused_automation_id -eq '1032' -and $beforeClear.focused_class -eq 'RICHEDIT50W') 'Telegram composer does not own focus before clear'
    Assert-That ($beforeClear.selected.id -eq 'telegram:user:1002' -and $beforeClear.bulk_selected_count -eq 0) 'Telegram clear started in the wrong selection'
    Add-Content (Join-Path $Session.evidence 'actions.log') 'telegram-clear: begin'
    if ($beforeClear.composer_text.Length -gt 0) { Send-Keys $Session '^a{BACKSPACE}' }
    Add-Content (Join-Path $Session.evidence 'actions.log') 'telegram-clear: end'
    $afterClear = Save-TelegramArchiveObservation $Session 'after-clear'
    Assert-That ($afterClear.focused_hwnd -eq $afterClear.composer_hwnd -and $afterClear.focused_automation_id -eq '1032' -and $afterClear.focused_class -eq 'RICHEDIT50W') 'Telegram composer lost focus during clear'
    Assert-That ($afterClear.composer_text -ceq '' -and $afterClear.selected.id -eq 'telegram:user:1002' -and $afterClear.bulk_selected_count -eq 0) 'Telegram clear changed the chat selection'
    Invoke-PaletteCommand $Session 'Verification Telegram'
    $null = Wait-Until { (Read-Control $Session status).selected.id -eq 'telegram:user:1001' } 'Telegram chat restored'
    $afterPalette = Save-TelegramArchiveObservation $Session 'after-palette'
    Assert-That ($afterPalette.selected.id -eq 'telegram:user:1001' -and $afterPalette.bulk_selected_count -eq 0) 'Telegram palette left a bulk selection'
    $beforeArchive = Save-TelegramArchiveObservation $Session 'before-archive'
    Assert-That ($beforeArchive.selected.id -eq 'telegram:user:1001' -and $beforeArchive.bulk_selected_count -eq 0) 'Telegram one-chat archive has a bulk selection'
    Send-Keys $Session '^e'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        -not $state.show_archived -and $state.pending_archives -eq 0 -and $state.chat_count -eq 4 -and
            $rows.Count -eq 4 -and @($rows | Where-Object id -eq 'telegram:user:1001').Count -eq 0
    } 'Telegram locally archived chat removed'
    Save-Screen $Session archived-inbox
    Invoke-PaletteCommand $Session 'Show archived chats'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats -Arguments @('--archived')).chats
        $state.show_archived -and $state.pending_archives -eq 0 -and $state.chat_count -eq 1 -and
            $state.selected.id -eq 'telegram:user:1001' -and $rows.Count -eq 1 -and
            $rows[0].id -eq 'telegram:user:1001' -and $rows[0].provider -eq 'telegram' -and $rows[0].archived
    } 'Telegram locally archived chat visible'
    Save-Screen $Session archived
    Send-Keys $Session '^e'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.show_archived -and $state.pending_archives -eq 0 -and $state.chat_count -eq 0 -and
            @((Read-Control $Session chats -Arguments @('--archived')).chats).Count -eq 0
    } 'Telegram unarchived chat removed from Archive'
    Save-Screen $Session unarchived-archive
    Invoke-PaletteCommand $Session 'Show inbox chats'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        -not $state.show_archived -and $state.pending_archives -eq 0 -and $state.chat_count -eq 5 -and
            $rows.Count -eq 5 -and @($rows | Where-Object { $_.id -eq 'telegram:user:1001' -and $_.provider -eq 'telegram' -and -not $_.archived }).Count -eq 1
    } 'Telegram unarchived chat restored to inbox'
    Assert-That (@(Read-BridgeRequests $Session | Where-Object { $_.method -eq 'POST' -and $_.path -eq '/v1/wazig/archive' -and $_.body.chat -eq 'telegram:user:1001' }).Count -eq 0) 'Telegram archive must stay local'
    Save-Screen $Session after
    Hub-Pass $Session local-archive-unarchive
}
