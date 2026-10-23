function Save-TelegramMessages($Session, [string]$Name) {
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.messages.json")
    Save-Screen $Session $Name
}

function Invoke-TelegramJourney($Session, [string]$Messages) {
    $null = Wait-Until { @((Read-Control $Session status).view_order | Where-Object provider -eq 'telegram').Count -eq 1 } 'Telegram view registered'
    $order = (Read-Control $Session status).view_order
    $number = 1
    while ($order[$number - 1].provider -ne 'telegram') { $number++ }
    Send-Keys $Session "%$number"
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.view -eq 'telegram' -and $state.current_view.account -eq 'telegram' -and $state.current_view.label -eq 'Telegram' -and $state.chat_count -eq 0 -and $state.telegram_link.unlinked -and $state.telegram_link.qr_ready
    } 'Telegram QR visible'
    Save-Screen $Session qr
    $requests = @(Read-BridgeRequests $Session)
    Assert-That (@($requests | Where-Object { $_.path -eq '/v1/wazig/telegram/link' -and $_.status -eq 200 }).Count -eq 1) 'Missing initial link status'
    Assert-That (@($requests | Where-Object { $_.path -eq '/v1/wazig/telegram/link.png' -and $_.status -eq 200 }).Count -eq 1) 'Missing QR fetch'
    Hub-Pass $Session linking-qr
    $dialog = Wait-Until {
        $foreground = [Windows.Automation.AutomationElement]::FromHandle([VerifyWindow]::GetForegroundWindow())
        if ($foreground.Current.ProcessId -eq $Session.pid -and $foreground.Current.ClassName -eq 'TelegramLogin') { return $foreground }
    } 'hub Telegram password field' 45
    $fields = $dialog.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'Edit'))
    Assert-That ($fields.Count -eq 1 -and $fields[0].Current.IsPassword) 'Expected exactly one protected password field'
    Save-Screen $Session password
    [System.Windows.Forms.SendKeys]::SendWait('synthetic-invalid')
    Add-Content (Join-Path $Session.evidence 'actions.log') 'keys: [synthetic password redacted]'
    Send-Keys $Session '{TAB}{ENTER}'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/telegram/password' -and $_.status -eq 401 }).Count -eq 1 -and $fields[0].Current.IsEnabled } 'invalid password retry'
    Save-Screen $Session password-invalid
    $foreground = [Windows.Automation.AutomationElement]::FromHandle([VerifyWindow]::GetForegroundWindow())
    Assert-That ($foreground.Current.ProcessId -eq $Session.pid -and $foreground.Current.ClassName -eq 'TelegramLogin') 'Password input lost ownership'
    [System.Windows.Forms.SendKeys]::SendWait('synthetic-accepted')
    Add-Content (Join-Path $Session.evidence 'actions.log') 'keys: [synthetic password redacted]'
    Send-Keys $Session '{TAB}{ENTER}'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/telegram/password' -and $_.status -eq 200 }).Count -eq 1 } 'password linked through hub'
    Hub-Pass $Session linking-password
    $null = Wait-Until { $state = Read-Control $Session status; $state.chat_count -eq 5 -and -not $state.telegram_link.unlinked } 'Telegram linked and chats loaded' 45
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
    Save-Screen $Session linked
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
        $foreground = [Windows.Automation.AutomationElement]::FromHandle([VerifyWindow]::GetForegroundWindow())
        if ($foreground.Current.ProcessId -eq $Session.pid -and $foreground.Current.ClassName -eq '#32770') { return [IntPtr]$foreground.Current.NativeWindowHandle }
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
    Send-Keys $Session '^a{BACKSPACE}'
    Invoke-PaletteCommand $Session 'Verification Telegram'
    $null = Wait-Until { (Read-Control $Session status).selected.id -eq 'telegram:user:1001' } 'Telegram chat restored'
    Invoke-PaletteCommand $Session 'Archive selected chat'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/archive' -and $_.body.chat -eq 'telegram:user:1001' -and $_.status -eq 502 }).Count -eq 1 -and (Read-Control $Session status).pending_archives -eq 0 } 'Telegram unsupported archive settled'
    Save-Screen $Session after
    Hub-Pass $Session archive-unsupported
}
