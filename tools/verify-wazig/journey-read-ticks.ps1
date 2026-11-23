$chats = @(
    @{ name = 'Verification Sent'; id = 'ticks-sent@s.whatsapp.net'; stage = 'ticks-sent'; ticks = 'sent'; inks = 'grey' },
    @{ name = 'Verification Delivered'; id = 'ticks-delivered@s.whatsapp.net'; stage = 'ticks-delivered'; ticks = 'delivered'; inks = 'grey' },
    @{ name = 'Verification Read'; id = 'ticks-read@s.whatsapp.net'; stage = 'ticks-read'; ticks = 'read'; inks = 'blue' },
    @{ name = 'Verification Late'; id = 'ticks-late@s.whatsapp.net'; stage = 'ticks-late'; ticks = 'delivered'; inks = 'grey'; older = 'read' },
    @{ name = 'Verification Group'; id = 'ticks-group@g.us'; stage = 'ticks-group'; ticks = 'delivered'; inks = 'grey' },
    @{ name = 'Verification Slack'; id = 'slack:fixture-ticks:channel'; stage = 'ticks-slack'; ticks = 'none'; inks = 'none' },
    @{ name = 'Verification Signal Contact'; id = 'signal:ticks-contact'; stage = 'ticks-signal'; ticks = 'read'; inks = 'blue' },
    @{ name = 'Verification Signal Crowd'; id = 'signal:group:ticks-group'; stage = 'ticks-signal-group'; ticks = 'none'; inks = 'none' },
    @{ name = 'Verification Telegram Contact'; id = 'telegram:user:ticks-contact'; stage = 'ticks-telegram'; ticks = 'read'; inks = 'blue' },
    @{ name = 'Verification Telegram Fresh'; id = 'telegram:user:ticks-unread'; stage = 'ticks-telegram-unread'; ticks = 'sent'; inks = 'grey' }
)
$canvas = (Get-Edit (Get-Window $session) '1024').Current.BoundingRectangle
$desktop = [System.Windows.Forms.SystemInformation]::VirtualScreen
$headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
$measured = @{}
function Measure-Ticks([string]$Path, $Band) {
    $image = [Drawing.Bitmap]::new($Path)
    try {
        $grey = 0
        $blue = 0
        for ($y = $Band.top; $y -lt $Band.bottom; $y++) {
            for ($x = $Band.left; $x -lt $Band.right; $x++) {
                if ($x -lt 0 -or $y -lt 0 -or $x -ge $image.Width -or $y -ge $image.Height) { continue }
                $pixel = $image.GetPixel($x, $y)
                if ([Math]::Abs([int]$pixel.R - 42) -le 64 -and [Math]::Abs([int]$pixel.G - 171) -le 64 -and [Math]::Abs([int]$pixel.B - 238) -le 64) {
                    $blue++
                } elseif ([Math]::Abs([int]$pixel.R - 138) -le 40 -and [Math]::Abs([int]$pixel.G - 138) -le 40 -and [Math]::Abs([int]$pixel.B - 138) -le 40) {
                    $grey++
                }
            }
        }
        return @{ grey = $grey; blue = $blue }
    } finally { $image.Dispose() }
}
function Get-TickBand($Bubble, $Canvas, $Desktop) {
    @{
        left = [int]($Canvas.Left + $Bubble[2] - 30) - $Desktop.Left
        right = [int]($Canvas.Left + $Bubble[2] - 8) - $Desktop.Left
        top = [int]($Canvas.Top + $Bubble[3] - 10) - $Desktop.Top
        bottom = [int]($Canvas.Top + $Bubble[3]) - $Desktop.Top
    }
}
function Get-TickPixels($Shown, [string]$Id, [string]$Path, $Canvas, $Desktop) {
    $row = @($Shown.messages | Where-Object { $_.id -eq $Id -and $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[3] -gt $_.bubble[1] })
    if ($row.Count -ne 1) { return $null }
    $band = Get-TickBand $row[0].bubble $Canvas $Desktop
    $pixels = Measure-Ticks $Path $band
    return @{ id = $Id; ticks = $row[0].ticks; bubble = @($row[0].bubble); grey = $pixels.grey; blue = $pixels.blue }
}
function Get-TopPainted($Shown) {
    $painted = @($Shown.messages | Where-Object { $_.bubble[1] -ne 0 -or $_.bubble[3] -ne 0 })
    if ($painted.Count -eq 0) { return $null }
    return @{ id = $painted[0].id; y = [int]$painted[0].bubble[1]; painted = $painted.Count }
}
function Assert-Inks($Chat, $Mark) {
    if ($Chat.inks -eq 'none') {
        Assert-That ($Mark.grey -eq 0 -and $Mark.blue -eq 0) "Ticks drawn on $($Chat.name) although it shows none: grey=$($Mark.grey) blue=$($Mark.blue)"
    } elseif ($Chat.inks -eq 'blue') {
        Assert-That ($Mark.blue -ge 8) "Read ticks missing on $($Chat.name): blue=$($Mark.blue)"
        Assert-That ($Mark.grey -le 4) "Read ticks are not blue on $($Chat.name): grey=$($Mark.grey)"
    } else {
        Assert-That ($Mark.grey -ge 6) "Grey ticks missing on $($Chat.name): grey=$($Mark.grey)"
        Assert-That ($Mark.blue -eq 0) "Blue ticks drawn on $($Chat.name) although it is not read: blue=$($Mark.blue)"
    }
}
foreach ($chat in $chats) {
    Send-Keys $session '^f'
    Send-Keys $session $chat.name
    $null = Wait-Until {
        $shown = Read-Control $session messages
        $marked = @($shown.messages | Where-Object { $_.id -eq 'tick-own' -and $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[3] -gt $_.bubble[1] })
        $shown.chat.id -eq $chat.id -and $marked.Count -eq 1
    } "own message painted in $($chat.name)"
    $shown = Read-Control $session messages
    $marked = @($shown.messages | Where-Object { $_.id -eq 'tick-own' })
    Assert-That ($marked.Count -eq 1) "Own message tick-own is not shown in $($chat.name)"
    Assert-That ($marked[0].ticks -eq $chat.ticks) "Read tick wrong in $($chat.name): ticks=$($marked[0].ticks) expected=$($chat.ticks)"
    $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence "$($chat.stage).messages.json")
    Save-Screen $session $chat.stage
    $mark = Get-TickPixels $shown 'tick-own' (Join-Path $session.evidence "$($chat.stage).png") $canvas $desktop
    Assert-That ($null -ne $mark) "Own message tick-own is not painted in $($chat.name)"
    Assert-Inks $chat $mark
    $mark | ConvertTo-Json | Set-Content (Join-Path $session.evidence "$($chat.stage).json")
    $measured[$chat.name] = $mark
    if ($chat.older) {
        $older = Get-TickPixels $shown 'tick-old' (Join-Path $session.evidence "$($chat.stage).png") $canvas $desktop
        Assert-That ($null -ne $older) "Older own message tick-old is not painted in $($chat.name)"
        Assert-That ($older.ticks -eq $chat.older) "Read tick wrong on the older message in $($chat.name): ticks=$($older.ticks) expected=$($chat.older)"
        Assert-That ($older.blue -ge 8) "Older read message shows no blue ticks in $($chat.name): blue=$($older.blue)"
        $older | ConvertTo-Json | Set-Content (Join-Path $session.evidence "$($chat.stage).older.json")
    }
    Hub-Pass $session "$($chat.stage)=$($chat.ticks) grey=$($mark.grey) blue=$($mark.blue)"
}
$sent = $measured['Verification Sent']
$delivered = $measured['Verification Delivered']
$read = $measured['Verification Read']
Assert-That ($delivered.grey -ge $sent.grey + 6) "Delivered does not show a second tick: sent grey=$($sent.grey) delivered grey=$($delivered.grey)"
Assert-That ($read.blue -ge 8) "Read does not show blue ticks: blue=$($read.blue)"
Send-Keys $session '^f'
Send-Keys $session 'Verification Hold'
$null = Wait-Until {
    $shown = Read-Control $session messages
    $hold = @($shown.messages | Where-Object { $_.id -eq 'hold-39' -and $_.bubble[3] -gt $_.bubble[1] })
    $shown.chat.id -eq 'ticks-hold@s.whatsapp.net' -and $hold.Count -eq 1 -and $hold[0].ticks -eq 'delivered'
} 'hold chat shows the delivered ticks before its newest message is read'
$before_shown = Read-Control $session messages
Save-Screen $session 'ticks-hold-delivered'
$before_mark = Get-TickPixels $before_shown 'hold-39' (Join-Path $session.evidence 'ticks-hold-delivered.png') $canvas $desktop
Assert-That ($null -ne $before_mark -and $before_mark.grey -ge 6 -and $before_mark.blue -eq 0) "Hold: delivered ticks missing: grey=$(if ($null -ne $before_mark) { $before_mark.grey } else { 'none' }) blue=$(if ($null -ne $before_mark) { $before_mark.blue } else { 'none' })"
$paints = (Read-Control $session status).paints.canvas
Send-Keys $session '{PGUP}'
$null = Wait-Until { (Read-Control $session status).paints.canvas -gt $paints } 'repaint after scrolling up'
$before = Get-TopPainted (Read-Control $session messages)
Assert-That ($null -ne $before -and $before.id -ne 'hold-39') 'Hold chat did not scroll away from its newest message'
$paints = (Read-Control $session status).paints.canvas
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/ticks/read" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
$null = Wait-Until {
    $shown = Read-Control $session messages
    $hold = @($shown.messages | Where-Object { $_.id -eq 'hold-39' })
    $hold.Count -eq 1 -and $hold[0].ticks -eq 'read'
} 'the newest hold message reports read' -Seconds 90
$null = Wait-Until { (Read-Control $session status).paints.canvas -gt $paints } 'repaint after the ticks turned read'
$after = Get-TopPainted (Read-Control $session messages)
Assert-That ($null -ne $after -and $after.id -eq $before.id) "Hold: top message changed from $($before.id) to $(if ($null -ne $after) { $after.id } else { 'none' })"
$moved = [Math]::Abs($after.y - $before.y)
Assert-That ($moved -le 2) "Hold: $($after.id) moved $moved px when the ticks turned read"
Send-Keys $session '^{END}'
$null = Wait-Until {
    $shown = Read-Control $session messages
    $hold = @($shown.messages | Where-Object { $_.id -eq 'hold-39' -and $_.bubble[3] -gt $_.bubble[1] })
    $hold.Count -eq 1 -and $hold[0].ticks -eq 'read'
} 'read ticks painted on the newest hold message'
$after_shown = Read-Control $session messages
Save-Screen $session 'ticks-hold-read'
$after_mark = Get-TickPixels $after_shown 'hold-39' (Join-Path $session.evidence 'ticks-hold-read.png') $canvas $desktop
Assert-That ($null -ne $after_mark -and $after_mark.blue -ge 8) "Hold: read ticks missing after the status changed: blue=$(if ($null -ne $after_mark) { $after_mark.blue } else { 'none' })"
$before_height = $before_mark.bubble[3] - $before_mark.bubble[1]
$after_height = $after_mark.bubble[3] - $after_mark.bubble[1]
Assert-That ($before_height -eq $after_height) "Hold: the bubble height changed from $before_height to $after_height when the ticks turned read"
Assert-That ($before_mark.bubble[3] -eq $after_mark.bubble[3]) "Hold: the bubble bottom moved from $($before_mark.bubble[3]) to $($after_mark.bubble[3]) when the ticks turned read"
@{ before = $before; after = $after; moved = $moved; bubble = @($after_mark.bubble); height = $after_height; grey_before = $before_mark.grey; blue_after = $after_mark.blue } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'ticks-hold.json')
Hub-Pass $session "ticks-hold=$($before.id) moved=$moved height=$after_height grey=$($before_mark.grey) blue=$($after_mark.blue)"
