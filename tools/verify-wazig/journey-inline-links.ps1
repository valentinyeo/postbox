. "$PSScriptRoot/menus.ps1"

function Read-InlineReceipts($Session) {
    $path = Join-Path $Session.root 'local/Messages/verification-url-launches.jsonl'
    if (-not (Test-Path $path)) { return @() }
    return @(Get-Content $path | Where-Object { $_.EndsWith('}') } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Capture-InlineStage($Session, [string]$Name, $Point = $null) {
    $state = Read-Control $Session status
    $shown = Read-Control $Session messages
    $receipts = @(Read-InlineReceipts $Session)
    $requests = @(Read-BridgeRequests $Session)
    $record = @{ name = $Name; point = $Point; status = $state; messages = $shown; receipts = $receipts; requests = $requests }
    $record | ConvertTo-Json -Depth 24 | Set-Content (Join-Path $Session.evidence "$Name.json")
    Focus-InlineApp $Session
    Save-Screen $Session $Name
    return $record
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

function Click-InlinePoint($Session, [int]$X, [int]$Y, [string]$Name) {
    Focus-InlineApp $Session
    $canvas = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
    $point = [VerifyWindow+Point]::new()
    $point.X = $X
    $point.Y = $Y
    Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$point)) 'Inline link canvas origin missing'
    [VerifyMenus]::Click($Session.pid, $point.X, $point.Y, $false)
    Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: $Name client=$X,$Y screen=$($point.X),$($point.Y)"
    return @{ client = @($X, $Y); screen = @($point.X, $point.Y) }
}

Send-Keys $session '^1'
Send-Keys $session '^f'
Send-Keys $session 'Verification Inline Links'
$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.chat.id -ceq 'fixture-alpha' -and @($shown.messages | Where-Object id -CEQ 'INLINE-REPLY').Count -eq 1
} 'inline links fixture loaded'
Click-Control $session '1032'
$null = Capture-InlineStage $session 'inline-loaded'
$null = Wait-Until {
    $rows = (Read-Control $session messages).messages
    $bodyRow = @($rows | Where-Object id -CEQ 'INLINE-BODY')[0]
    $replyRow = @($rows | Where-Object id -CEQ 'INLINE-REPLY')[0]
    $bodyRow.links.Count -gt 0 -and $replyRow.quote_line[2] -gt $replyRow.quote_line[0]
} 'inline links painted'
$initial = Capture-InlineStage $session 'inline-before'
$body = @($initial.messages.messages | Where-Object id -CEQ 'INLINE-BODY')[0]
$plain = @($initial.messages.messages | Where-Object id -CEQ 'INLINE-PLAIN')[0]
$reply = @($initial.messages.messages | Where-Object id -CEQ 'INLINE-REPLY')[0]
$bodyUrl = "$($session.bridge_url)/inline-links/body-" + ('abcdefghij' * 18)
$quoteUrl = "$($session.bridge_url)/inline-links/quote-" + ('klmnopqrst' * 18)
@{ body = $bodyUrl; quote = $quoteUrl; app_pid = $session.pid; session = $session.id; bridge = $session.bridge_url } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'inline-targets.json')
Assert-That ($body.links.Count -eq 1 -and $body.links[0] -ceq $bodyUrl) 'Body fixture link missing'
Assert-That ($reply.quote -ceq $quoteUrl -and $reply.quote_line[2] -gt $reply.quote_line[0]) 'Reply fixture quote missing'
$fragments = @($body.link_rects[0] | Where-Object { $_[2] -gt $_[0] -and $_[3] -gt $_[1] })
Assert-That ($fragments.Count -ge 2) 'Body link did not wrap into painted fragments'

$rect = $fragments[0]
$point = Click-InlinePoint $session ([int](($rect[0] + $rect[2]) / 2)) ([int](($rect[1] + $rect[3]) / 2)) 'body-first'
$first = Capture-InlineStage $session 'inline-body-first' $point
$rect = $fragments[-1]
$point = Click-InlinePoint $session ([int](($rect[0] + $rect[2]) / 2)) ([int](($rect[1] + $rect[3]) / 2)) 'body-last'
$last = Capture-InlineStage $session 'inline-body-last' $point
$rect = $plain.bubble
$point = Click-InlinePoint $session ([int](($rect[0] + $rect[2]) / 2)) ([int](($rect[1] + $rect[3]) / 2)) 'plain-text'
$nonlink = Capture-InlineStage $session 'inline-plain' $point

Focus-InlineApp $session
Send-Keys $session '^o'
$palette = Get-PaletteWindow $session
Save-Screen $session 'inline-palette'
Send-Keys $session 'body-'
$edit = Get-Edit $palette '1064'
$null = Wait-Until { (Read-Edit $edit) -ceq 'body-' } 'inline links palette query'
Send-Keys $session '{ENTER}'
$shortcut = Capture-InlineStage $session 'inline-ctrl-o'

$rect = $reply.quote_line
$x = [int]($rect[0] + ($rect[2] - $rect[0]) / 2)
$y = [int](($rect[1] + $rect[3]) / 2)
$point = Click-InlinePoint $session $x $y 'quote-url'
$quote = Capture-InlineStage $session 'inline-quote' $point

$stages = @($initial, $first, $last, $nonlink, $shortcut, $quote)
$stages | ConvertTo-Json -Depth 24 | Set-Content (Join-Path $session.evidence 'inline-stages.json')
$writes = @($quote.requests | Where-Object { $_.wire_path -match '^/v1/wazig/(send|react|archive)' })
Assert-That ($writes.Count -eq 0 -and $quote.status.pending_sends -eq 0) 'Inline journey caused a send or other write'
Assert-That ($initial.receipts.Count -eq 0) 'Unexpected launch before inline input'
Assert-That ($first.receipts.Count -eq 1 -and $first.receipts[-1].url -ceq $bodyUrl) 'Body first fragment did not dispatch its complete URL'
Assert-That ($last.receipts.Count -eq 2 -and $last.receipts[-1].url -ceq $bodyUrl) 'Body last fragment did not dispatch its complete URL'
Assert-That ($nonlink.receipts.Count -eq $last.receipts.Count) 'Plain text unexpectedly dispatched a URL'
Assert-That ($shortcut.receipts.Count -eq 3 -and $shortcut.receipts[-1].url -ceq $bodyUrl) 'Ctrl+O did not dispatch the body URL'
foreach ($receipt in $shortcut.receipts) {
    Assert-That ($receipt.pid -eq $session.pid -and $receipt.session -ceq $session.id -and $receipt.result -gt 32) 'Windows did not accept the real URL dispatch'
}
Assert-That ($quote.receipts.Count -eq 4 -and $quote.receipts[-1].url -ceq $quoteUrl -and $quote.receipts[-1].result -gt 32) 'Quoted reply URL did not dispatch through Windows'
