function Save-SignalMessages($Session, [string]$Name) {
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.messages.json")
    Save-Screen $Session $Name
}

function Invoke-SignalJourney($Session, [string]$Messages) {
    $null = Wait-Until { @((Read-Control $Session status).view_order | Where-Object provider -eq 'signal').Count -eq 1 } 'Signal view registered'
    $order = (Read-Control $Session status).view_order
    $number = 1
    while ($order[$number - 1].provider -ne 'signal') { $number++ }
    Send-Keys $Session "%$number"
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.view -eq 'signal' -and $state.current_view.account -eq 'signal' -and $state.current_view.label -eq 'Signal' -and $state.chat_count -eq 0 -and $state.signal_link.unlinked -and $state.signal_link.qr_ready
    } 'Signal QR visible'
    Save-Screen $Session qr
    $requests = @(Read-BridgeRequests $Session)
    Assert-That (@($requests | Where-Object { $_.path -eq '/v1/wazig/signal/link' -and $_.status -eq 200 }).Count -eq 1) 'Missing initial link status'
    Assert-That (@($requests | Where-Object { $_.path -eq '/v1/wazig/signal/link.png' -and $_.status -eq 200 }).Count -eq 1) 'Missing QR fetch'
    Hub-Pass $Session linking-qr
    $null = Wait-Until { $state = Read-Control $Session status; $state.chat_count -eq 4 -and -not $state.signal_link.unlinked } 'Signal linked and chats loaded' 45
    $rows = (Read-Control $Session chats).chats
    Assert-That (@($rows | Where-Object { $_.provider -ne 'signal' -or $_.view_account -ne 'signal' }).Count -eq 0) 'Signal view includes another account'
    Save-Screen $Session linked
    $sidebar = (Get-Edit (Get-Window $Session) '1016').Current.BoundingRectangle
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $image = [Drawing.Bitmap]::new((Join-Path $Session.evidence 'linked.png'))
    $blue = 0
    try {
        for ($y = [int]$sidebar.Top; $y -lt [int][Math]::Min($sidebar.Bottom, $sidebar.Top + 400); $y++) {
            for ($x = [int]$sidebar.Left; $x -lt [int][Math]::Min($sidebar.Right, $sidebar.Left + 100); $x++) {
                $pixel = $image.GetPixel($x - $screen.Left, $y - $screen.Top)
                if ($pixel.R -eq 58 -and $pixel.G -eq 118 -and $pixel.B -eq 240) { $blue++ }
            }
        }
    } finally { $image.Dispose() }
    Assert-That ($blue -gt 20) 'Signal blue row marks are not painted'
    @{ brand_blue_pixels = $blue } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'marks.json')
    Hub-Pass $Session linked-chats
    Invoke-PaletteCommand $Session 'Verification Signal'
    $null = Wait-Until { $shown = Read-Control $Session messages; $shown.chat.id -eq 'signal:fixture-contact' -and @($shown.messages | Where-Object id -eq 'fixture-sender:1000').Count -eq 1 } 'Signal history'
    Save-SignalMessages $Session history
    Assert-That (@(Read-BridgeRequests $Session | Where-Object { $_.path.StartsWith('/v1/wazig/messages?') -and $_.path.Contains('signal%3Afixture-contact') -and $_.status -eq 200 }).Count -gt 0) 'Signal history bypassed the hub'
    Hub-Pass $Session history
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/mark-read' -and $_.body.chat -eq 'signal:fixture-contact' -and $_.body.message_id -match '^fixture-sender:100[01]$' -and $_.status -eq 200 }).Count -gt 0 } 'Signal read receipt'
    $null = Wait-Until { @((Read-Control $Session chats).chats | Where-Object { $_.id -eq 'signal:fixture-contact' -and -not $_.unread }).Count -eq 1 } 'Signal unread cleared'
    Save-Screen $Session read
    Hub-Pass $Session mark-read
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path.StartsWith('/v1/wazig/media/') -and $_.status -eq 200 }).Count -gt 0 } 'Signal automatic media download'
    $null = Wait-Until { @(Get-ChildItem (Join-Path $Messages 'hub-media') -Filter '*.bin' | Where-Object Length -gt 0).Count -gt 0 } 'Signal media cached'
    Hub-Pass $Session media
    Send-Keys $Session '%k'
    Invoke-PaletteCommand $Session 'Like'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/react' -and $_.body.chat -eq 'signal:fixture-contact' -and $_.body.msg -eq 'fixture-sender:1001' -and $_.status -eq 200 }).Count -eq 1 } 'Signal reaction acknowledged'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object { $_.id -eq 'fixture-sender:1001' -and $_.reaction -eq ([char]::ConvertFromUtf32(0x1f44d)) }).Count -eq 1 } 'Signal reaction visible'
    Save-SignalMessages $Session reacted
    Hub-Pass $Session react
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session 'Synthetic Signal outgoing'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.body.text -eq 'Synthetic Signal outgoing' -and $_.accepted -and -not $_.multipart }).Count -eq 1 -and (Read-Control $Session status).pending_sends -eq 0 } 'Signal text accepted'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object text -eq 'Synthetic Signal outgoing').Count -eq 1 } 'Signal text visible'
    Save-SignalMessages $Session text
    Hub-Pass $Session send-text
    $file = Join-Path $Session.root 'fixture.png'
    $image = [Drawing.Bitmap]::new(32, 32)
    try { $image.Save($file, [Drawing.Imaging.ImageFormat]::Png) } finally { $image.Dispose() }
    @{ sha256 = (Get-FileHash $file).Hash.ToLowerInvariant(); size = (Get-Item $file).Length } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'file.json')
    Invoke-PaletteCommand $Session 'Attach photo or file'
    $picker = Wait-Until {
        $foreground = [Windows.Automation.AutomationElement]::FromHandle([VerifyWindow]::GetForegroundWindow())
        if ($foreground.Current.ProcessId -eq $Session.pid -and $foreground.Current.ClassName -eq '#32770') { return $foreground }
    } 'owned attachment picker'
    $filenameCondition = [Windows.Automation.AndCondition]::new(
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit),
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'File name:')
    )
    $filename = Wait-Until { $picker.FindFirst([Windows.Automation.TreeScope]::Descendants, $filenameCondition) } 'attachment filename edit'
    $value = $filename.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
    $value.SetValue($file)
    Assert-That ($value.Current.Value -ceq $file) 'Attachment filename was not set'
    $open = Get-Edit $picker '1'
    $open.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
    Add-Content (Join-Path $Session.evidence 'actions.log') 'uia: attachment filename set and Open invoked'
    $null = Wait-Until { [VerifyWindow]::GetForegroundWindow() -eq (Get-App $Session).MainWindowHandle } 'attachment picker closed'
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session 'Synthetic Signal file'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.multipart -and $_.accepted -and $_.body.chat -eq 'signal:fixture-contact' -and $_.file_sha256 -eq (Get-FileHash $file).Hash.ToLowerInvariant() }).Count -eq 1 -and (Read-Control $Session status).pending_sends -eq 0 } 'Signal multipart bytes accepted'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object { $_.text -eq 'Synthetic Signal file' -and $_.media_type -eq 'image' }).Count -eq 1 } 'Signal file visible'
    Save-SignalMessages $Session file
    Hub-Pass $Session send-file
    Invoke-RestMethod "$($Session.bridge_url)/fixture/live" -Method Post -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' | Out-Null
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object id -eq 'fixture-sender:1002').Count -eq 1 } 'Signal live event visible'
    Save-SignalMessages $Session live
    Hub-Pass $Session live-events
    foreach ($failure in @(@{ chat = 'Verification Limited'; id = 'signal:fixture-limited'; reason = 'signal rate limited'; code = 429; name = 'limited' }, @{ chat = 'Verification Captcha'; id = 'signal:fixture-captcha'; reason = 'signal captcha required'; code = 403; name = 'captcha' })) {
        Invoke-PaletteCommand $Session $failure.chat
        $null = Wait-Until { $shown = Read-Control $Session messages; $shown.chat.id -eq $failure.id -and $shown.messages.Count -gt 0 } 'Signal rejection chat open'
        Invoke-PaletteCommand $Session 'Compose message'
        Send-Keys $Session 'Synthetic rejected send'
        Send-Keys $Session '{ENTER}'
        $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object { $_.send_state -eq 'failed' -and $_.text.Contains($failure.reason) }).Count -eq 1 -and (Read-Control $Session status).pending_sends -eq 0 } 'Signal failure reason visible without retry'
        Save-SignalMessages $Session $failure.name
        Assert-That (@(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.body.chat -eq $failure.id -and $_.status -eq $failure.code }).Count -eq 1) 'Signal rejection was retried or hidden'
        Hub-Pass $Session $failure.name
        Send-Keys $Session '^a{BACKSPACE}'
    }
    Invoke-PaletteCommand $Session 'Verification Signal'
    $null = Wait-Until { (Read-Control $Session status).selected.id -eq 'signal:fixture-contact' } 'Signal chat restored'
    Invoke-PaletteCommand $Session 'Archive selected chat'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/archive' -and $_.body.chat -eq 'signal:fixture-contact' -and $_.status -eq 502 }).Count -eq 1 -and (Read-Control $Session status).pending_archives -eq 0 } 'Signal unsupported archive settled'
    Save-Screen $Session after
    Hub-Pass $Session archive-unsupported
}
