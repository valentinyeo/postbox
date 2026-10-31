Add-Type -Path "$PSScriptRoot/inline-links-native.cs"

function Save-InlineStages($Session) {
    ConvertTo-Json -InputObject @($script:inlineStages.ToArray()) -Depth 32 | Set-Content (Join-Path $Session.evidence 'inline-stages.json')
}

function Record-InlineStage($Session, $Record) {
    $script:inlineStages.Add($Record)
    Save-InlineStages $Session
}

function Focus-InlineApp($Session) {
    $app = Get-App $Session
    $null = Wait-Until {
        [VerifyWindow]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
        $foreground = [VerifyWindow]::GetForegroundWindow()
        $owner = [uint32]0
        if ($foreground -ne [IntPtr]::Zero) { [VerifyWindow]::GetWindowThreadProcessId($foreground, [ref]$owner) | Out-Null }
        $owner -eq $Session.pid
    } 'inline links app foreground'
}

function Read-InlineReceipts($Session) {
    $path = Join-Path $Session.root 'local/Messages/verification-url-launches.jsonl'
    if (-not (Test-Path $path)) { return @() }
    return @(Get-Content $path | Where-Object { $_.EndsWith('}') } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Wait-InlineReceipt($Session, [int]$Count, [string]$Url) {
    $null = Wait-Until {
        $rows = @(Read-InlineReceipts $Session)
        $rows.Count -eq $Count -and $rows[-1].url -ceq $Url -and $rows[-1].pid -eq $Session.pid -and $rows[-1].session -ceq $Session.id
    } "exact receipt $Count"
}

function Screen-InlinePoint($Session, [int]$X, [int]$Y) {
    $canvas = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
    $point = [VerifyWindow+Point]::new()
    $point.X = $X; $point.Y = $Y
    Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$point)) 'Inline canvas origin missing'
    return $point
}

function Invoke-InlineClick($Session, [int]$X, [int]$Y, [string]$Name, [string]$Url = '', [bool]$Drag = $false, [bool]$Control = $false) {
    Focus-InlineApp $Session
    $before = Read-Control $Session status
    $receiptsBefore = @(Read-InlineReceipts $Session).Count
    $point = Screen-InlinePoint $Session $X $Y
    $endX = if ($Drag) { $X + 25 } else { $X }
    $end = Screen-InlinePoint $Session $endX $Y
    $path = Join-Path $Session.evidence "inline-input-$Name.json"
    @{ name=$Name; point=@($X,$Y); end=@($endX,$Y); before=$before.canvas_up_count; receipts=@(Read-InlineReceipts $Session) } | ConvertTo-Json -Depth 32 | Set-Content $path
    if ($Drag) { [InlineLinksNative]::Drag($Session.pid, $point.X, $point.Y, $end.X, $end.Y) }
    elseif ($Control) { [InlineLinksNative]::ControlClick($Session.pid, $point.X, $point.Y) }
    else { [InlineLinksNative]::Click($Session.pid, $point.X, $point.Y) }
    $ack = Wait-Until {
        $state = Read-Control $Session status
        if ($state.canvas_up_count -eq ($before.canvas_up_count + 1) -and [Math]::Abs($state.canvas_up_point[0] - $endX) -le 1 -and [Math]::Abs($state.canvas_up_point[1] - $Y) -le 1) { $state }
    } "handled canvas mouse-up $Name"
    $record = @{ name=$Name; point=@($X,$Y); end=@($endX,$Y); before=$before.canvas_up_count; jump_before=$before.reply_jump_count; ack=$ack.canvas_up_count; ack_point=$ack.canvas_up_point; receipts=@(Read-InlineReceipts $Session); status=$ack }
    $record | ConvertTo-Json -Depth 32 | Set-Content $path
    if ($Url) { Wait-InlineReceipt $Session ($receiptsBefore + 1) $Url }
    $record.receipts = @(Read-InlineReceipts $Session)
    $record | ConvertTo-Json -Depth 32 | Set-Content $path
    Assert-That ($record.receipts.Count -eq ($receiptsBefore + [int][bool]$Url)) "Unexpected dispatch count: $Name"
    Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: $Name client=$X,$Y end=$endX,$Y"
    return $record
}

function Get-InlineRow($Session, [string]$Id) {
    $rows = @((Read-Control $Session messages).messages | Where-Object id -CEQ $Id)
    Assert-That ($rows.Count -eq 1) "Missing synthetic message $Id"
    return $rows[0]
}

function Center-Inline($Rect) { return @([int](($Rect[0] + $Rect[2]) / 2), [int](($Rect[1] + $Rect[3]) / 2)) }

function Hover-Inline($Session, $Rect, [bool]$Hand, [string]$Name) {
    Focus-InlineApp $Session
    $p = Center-Inline $Rect
    $screen = Screen-InlinePoint $Session $p[0] $p[1]
    $canvas = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
    $client = [VerifyWindow+Rect]::new()
    Assert-That ([VerifyWindow]::GetClientRect($canvas, [ref]$client)) 'Inline canvas bounds missing'
    $offset = if ($p[0] + 8 -lt $client.Right) { 8 } else { -8 }
    $before = (Read-Control $Session status).canvas_cursor_count
    @{ point=$p; screen=@($screen.X,$screen.Y); before=$before } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "inline-cursor-$Name.json")
    [InlineLinksNative]::Hover($Session.pid, ($screen.X + $offset), $screen.Y)
    [InlineLinksNative]::Hover($Session.pid, $screen.X, $screen.Y)
    $ack = Wait-Until {
        $state = Read-Control $Session status
        if ($state.canvas_cursor_count -gt $before -and [Math]::Abs($state.canvas_cursor_point[0] - $p[0]) -le 1 -and [Math]::Abs($state.canvas_cursor_point[1] - $p[1]) -le 1) { $state }
    } "handled canvas cursor $Name"
    $cursor = [InlineLinksNative]::Cursor()
    $record = @{ point=$p; screen=@($screen.X,$screen.Y); before=$before; ack=$ack.canvas_cursor_count; ack_point=$ack.canvas_cursor_point; cursor=$cursor[0]; hand=$cursor[1]; cursor_screen=@($cursor[2],$cursor[3]); flags=$cursor[4] }
    $record | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "inline-cursor-$Name.json")
    Assert-That ([Math]::Abs($cursor[2] - $screen.X) -le 1 -and [Math]::Abs($cursor[3] - $screen.Y) -le 1 -and (($cursor[0] -eq $cursor[1]) -eq $Hand)) "Native cursor shape: $Name"
    return $record
}

function Measure-InlineUnderline($Session, [string]$Name, $Rect) {
    Focus-InlineApp $Session
    Save-Screen $Session $Name
    $origin = Screen-InlinePoint $Session 0 0
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $image = [Drawing.Bitmap]::new((Join-Path $Session.evidence "$Name.png"))
    try {
        $best = 0
        $left = [int]($origin.X + $Rect[0] - $screen.Left)
        $right = [int]($origin.X + $Rect[2] - $screen.Left)
        $bottom = [int]($origin.Y + $Rect[3] - $screen.Top)
        for ($y = $bottom - 4; $y -lt $bottom; $y++) {
            $run = 0
            for ($x = $left; $x -lt $right; $x++) {
                $c = $image.GetPixel($x, $y)
                if ($c.R -ge 170 -and $c.G -ge 170 -and $c.B -ge 170) { $run++; $best = [Math]::Max($best, $run) } else { $run = 0 }
            }
        }
        $record = @{ screenshot="$Name.png"; rect=$Rect; pixel_rect=@($left, ($bottom - 4), $right, $bottom); longest_bright_run=$best }
        $record | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.json")
        Assert-That ($best -ge 8) "Visible underline missing: $Name"
        return $record
    } finally { $image.Dispose() }
}

$cases = @(
    @{ provider='whatsapp'; name='Verification Inline WhatsApp'; id='fixture-alpha' },
    @{ provider='slack'; name='Verification Inline Slack'; id='slack:fixture-inline:channel' },
    @{ provider='signal'; name='Verification Inline Signal'; id='signal:fixture-inline' },
    @{ provider='telegram'; name='Verification Inline Telegram'; id='telegram:user:7199' }
)
$script:inlineStages = [System.Collections.Generic.List[object]]::new()
$targets = @{}
foreach ($case in $cases) {
    Focus-InlineApp $session
    [InlineLinksNative]::Combo(0x31)
    [InlineLinksNative]::Combo(0x46)
    [InlineLinksNative]::Combo(0x41)
    [InlineLinksNative]::Text($case.name)
    $null = Wait-Until {
        $shown = Read-Control $session messages
        $shown.chat.id -ceq $case.id -and @($shown.messages | Where-Object id -CEQ 'INLINE-REPLY').Count -eq 1
    } "fixture $($case.provider) loaded"
    $null = Wait-Until {
        $rows = (Read-Control $session messages).messages
        $reply = @($rows | Where-Object id -CEQ 'INLINE-REPLY')[0]
        $reply.quote_fragments.Count -gt 0
    } "fixture $($case.provider) painted"
    $bodyUrl = "$($session.bridge_url)/inline-links/$($case.provider)-body-" + ('abcdefghij' * 18)
    $quoteUrl = "$($session.bridge_url)/inline-links/$($case.provider)-quote-" + ('klmnopqrst' * 18)
    $fallbackUrl = "$($session.bridge_url)/inline-links/$($case.provider)-fallback-" + ('uvwxyzabcd' * 18)
    $targets[$case.provider] = @{ body=$bodyUrl; quote=$quoteUrl; fallback=$fallbackUrl; id=$case.id }
    @{ session=$session.id; app_pid=$session.pid; bridge=$session.bridge_url; providers=$targets } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'inline-targets.json')
    $shown = Read-Control $session messages
    Record-InlineStage $session @{ name="$($case.provider)-fixture"; messages=$shown }
    $body = Get-InlineRow $session 'INLINE-BODY'
    $reply = Get-InlineRow $session 'INLINE-REPLY'
    $fragments = @($reply.quote_fragments | Where-Object { $_.rect[2] -gt $_.rect[0] })
    Assert-That ($reply.quote -ceq $quoteUrl -and $fragments.Count -gt 0) 'Compact quote URL missing'
    if ($case.provider -ceq 'whatsapp') {
        $bodyRects = @($body.link_rects[0] | Where-Object { $_[2] -gt $_[0] -and $_[1] -ge 72 })
        Assert-That ($body.links.Count -eq 1 -and $body.links[0] -ceq $bodyUrl -and $bodyRects.Count -ge 2) 'Wrapped body fixture missing'
        $plainWord = @($body.words | Where-Object { $_.start -eq 0 })[0].rect
        $handBody = Hover-Inline $session $bodyRects[0] $true 'body'
        $handQuote = Hover-Inline $session $fragments[0].rect $true 'quote'
        $arrow = Hover-Inline $session $plainWord $false 'plain'
        $bodyStyle = Measure-InlineUnderline $session 'inline-body-style' $bodyRects[0]
        $quoteStyle = Measure-InlineUnderline $session 'inline-quote-style' $fragments[0].rect
        Record-InlineStage $session @{name='appearance'; body_cursor=$handBody; quote_cursor=$handQuote; plain_cursor=$arrow; body_style=$bodyStyle; quote_style=$quoteStyle; messages=$shown}
        $point = Center-Inline $bodyRects[0]
        Record-InlineStage $session (Invoke-InlineClick $session $point[0] $point[1] 'body-first' $bodyUrl)
        $point = Center-Inline $bodyRects[-1]
        Record-InlineStage $session (Invoke-InlineClick $session $point[0] $point[1] 'body-last' $bodyUrl)
        $point = Center-Inline $plainWord
        Record-InlineStage $session (Invoke-InlineClick $session $point[0] $point[1] 'plain')
        $marked = Invoke-InlineClick $session $point[0] $point[1] 'mark' '' $false $true
        $marked['marked'] = (Get-InlineRow $session 'INLINE-BODY').marked
        Record-InlineStage $session $marked
        Assert-That $marked.marked 'Control-click did not mark the message'
        $unmarked = Invoke-InlineClick $session $point[0] $point[1] 'unmark' '' $false $true
        $unmarked['marked'] = (Get-InlineRow $session 'INLINE-BODY').marked
        Record-InlineStage $session $unmarked
        Assert-That (-not $unmarked.marked) 'Control-click did not unmark the message'
        $point = Center-Inline $fragments[0].rect
        Record-InlineStage $session (Invoke-InlineClick $session $point[0] $point[1] 'quote-drag' '' $true)
        $out = Get-InlineRow $session 'INLINE-OUT'
        Assert-That ($out.from_me -and $out.quote_fragments.Count -gt 0) 'Outgoing compact quote missing'
        $point = Center-Inline $out.quote_fragments[0].rect
        Record-InlineStage $session (Invoke-InlineClick $session $point[0] $point[1] 'quote-outgoing' $quoteUrl)
        $block = Get-InlineRow $session 'INLINE-BLOCK'
        Assert-That ($block.quoted_msg_id -ceq '' -and $block.quote_fragments.Count -ge 2) 'Two-line fallback quote missing'
        $point = Center-Inline $block.quote_fragments[1].rect
        Record-InlineStage $session (Invoke-InlineClick $session $point[0] $point[1] 'quote-fallback' $fallbackUrl)
        Focus-InlineApp $session
        $before = @(Read-InlineReceipts $session).Count
        [InlineLinksNative]::Combo(0x4F)
        $palette = Get-PaletteWindow $session
        $list = Get-Edit $palette '1072'
        $count = Read-ListCount $list
        Assert-That ($count -eq 1) 'Ctrl+O included quote-only URLs or lost the body URL'
        [InlineLinksNative]::Text('body-')
        $edit = Get-Edit $palette '1064'
        $null = Wait-Until { (Read-Edit $edit) -ceq 'body-' } 'body link palette query'
        Save-Screen $session 'inline-palette'
        [InlineLinksNative]::Press(0x0D)
        Wait-InlineReceipt $session ($before + 1) $bodyUrl
        Record-InlineStage $session @{ name='ctrl-o'; palette_count=$count; receipts=@(Read-InlineReceipts $session) }
    }
    $reply = Get-InlineRow $session 'INLINE-REPLY'
    $point = Center-Inline $reply.quote_fragments[0].rect
    Record-InlineStage $session (Invoke-InlineClick $session $point[0] $point[1] "$($case.provider)-incoming" $quoteUrl)
    if ($case.provider -ceq 'whatsapp') {
        $reply = Get-InlineRow $session 'INLINE-REPLY'
        $x = [int]($reply.quote_line[0] + 4); $y = [int](($reply.quote_line[1] + $reply.quote_line[3]) / 2)
        $jump = Invoke-InlineClick $session $x $y 'quote-jump'
        Record-InlineStage $session $jump
        Assert-That ($jump.status.reply_jump_count -eq ($jump.jump_before + 1) -and $jump.status.reply_jump_id -ceq 'INLINE-BODY') 'Ordinary quote navigation failed'
    }
}
@{ session=$session.id; app_pid=$session.pid; bridge=$session.bridge_url; providers=$targets } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'inline-targets.json')
Save-InlineStages $session
