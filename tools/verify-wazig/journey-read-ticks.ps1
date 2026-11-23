$chats = @(
    @{ name = 'Verification Read'; id = 'ticks-read@s.whatsapp.net'; shown = $true; tick = 'tick-own'; mark = 'tick-own'; stage = 'ticks-read' },
    @{ name = 'Verification Sent'; id = 'ticks-sent@s.whatsapp.net'; shown = $false; tick = ''; mark = 'tick-own'; stage = 'ticks-sent' },
    @{ name = 'Verification Late'; id = 'ticks-late@s.whatsapp.net'; shown = $true; tick = 'tick-old'; mark = 'tick-old'; clear = 'tick-own'; stage = 'ticks-late' },
    @{ name = 'Verification Group'; id = 'ticks-group@g.us'; shown = $false; tick = 'tick-own'; mark = 'tick-own'; stage = 'ticks-group' },
    @{ name = 'Verification Slack'; id = 'slack:fixture-ticks:channel'; shown = $false; tick = 'tick-own'; mark = 'tick-own'; stage = 'ticks-slack' },
    @{ name = 'Verification Signal Contact'; id = 'signal:ticks-contact'; shown = $true; tick = 'tick-own'; mark = 'tick-own'; stage = 'ticks-signal' },
    @{ name = 'Verification Signal Crowd'; id = 'signal:group:ticks-group'; shown = $false; tick = 'tick-own'; mark = 'tick-own'; stage = 'ticks-signal-group' },
    @{ name = 'Verification Telegram Contact'; id = 'telegram:user:ticks-contact'; shown = $true; tick = 'tick-own'; mark = 'tick-own'; stage = 'ticks-telegram' },
    @{ name = 'Verification Telegram Fresh'; id = 'telegram:user:ticks-unread'; shown = $false; tick = ''; mark = 'tick-own'; stage = 'ticks-telegram-unread' }
)
$canvas = (Get-Edit (Get-Window $session) '1024').Current.BoundingRectangle
$desktop = [System.Windows.Forms.SystemInformation]::VirtualScreen
function Measure-ReadMark([string]$Path, [int]$Left, [int]$Top, [int]$Right, [int]$Bottom) {
    $image = [Drawing.Bitmap]::new($Path)
    try {
        $blue = 0
        for ($y = $Top; $y -lt $Bottom; $y++) {
            for ($x = $Left; $x -lt $Right; $x++) {
                if ($x -lt 0 -or $y -lt 0 -or $x -ge $image.Width -or $y -ge $image.Height) { continue }
                $pixel = $image.GetPixel($x, $y)
                if ([Math]::Abs([int]$pixel.R - 42) -le 64 -and [Math]::Abs([int]$pixel.G - 171) -le 64 -and [Math]::Abs([int]$pixel.B - 238) -le 64) { $blue++ }
            }
        }
        return $blue
    } finally { $image.Dispose() }
}
function Get-ReadMarkBand($Bubble, $Canvas, $Desktop) {
    @{
        left = [int]($Canvas.Left + $Bubble[2] - 120) - $Desktop.Left
        right = [int]($Canvas.Left + $Bubble[2] + 4) - $Desktop.Left
        top = [int]($Canvas.Top + $Bubble[3] + 1) - $Desktop.Top
        bottom = [int]($Canvas.Top + $Bubble[3] + 32) - $Desktop.Top
    }
}
function Get-BlueBelow($Shown, [string]$Id, [string]$Path, $Canvas, $Desktop) {
    $row = @($Shown.messages | Where-Object { $_.id -eq $Id -and $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[3] -gt $_.bubble[1] })
    if ($row.Count -ne 1) { return $null }
    $band = Get-ReadMarkBand $row[0].bubble $Canvas $Desktop
    return @{ bubble = @($row[0].bubble); blue_below = (Measure-ReadMark $Path $band.left $band.top $band.right $band.bottom) }
}
foreach ($chat in $chats) {
    Send-Keys $session '^f'
    Send-Keys $session $chat.name
    $null = Wait-Until {
        $state = Read-Control $session status
        $shown = Read-Control $session messages
        $marked = @($shown.messages | Where-Object { $_.id -eq $chat.mark -and $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[3] -gt $_.bubble[1] })
        $shown.chat.id -eq $chat.id -and $marked.Count -eq 1 -and $state.read_tick.message -eq $chat.tick
    } "marked own message painted in $($chat.name)"
    $state = Read-Control $session status
    Assert-That ($state.read_tick.shown -eq $chat.shown) "Read tick wrong in $($chat.name): shown=$($state.read_tick.shown) expected=$($chat.shown)"
    Assert-That ($state.read_tick.message -eq $chat.tick) "Read tick names $($state.read_tick.message) in $($chat.name), expected $($chat.tick)"
    $state.read_tick | ConvertTo-Json | Set-Content (Join-Path $session.evidence "$($chat.stage).json")
    $shown = Read-Control $session messages
    $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence "$($chat.stage).messages.json")
    Save-Screen $session $chat.stage
    $mark = Get-BlueBelow $shown $chat.mark (Join-Path $session.evidence "$($chat.stage).png") $canvas $desktop
    Assert-That ($null -ne $mark) "Marked message $($chat.mark) is not painted in $($chat.name)"
    $mark | ConvertTo-Json | Set-Content (Join-Path $session.evidence "$($chat.stage).mark.json")
    if ($chat.shown) {
        Assert-That ($mark.blue_below -ge 6) "Read mark missing under $($chat.mark) in $($chat.name): blue=$($mark.blue_below)"
    } else {
        Assert-That ($mark.blue_below -eq 0) "Read mark drawn under $($chat.mark) in $($chat.name) although it shows none: blue=$($mark.blue_below)"
    }
    if ($chat.clear) {
        $clear = Get-BlueBelow $shown $chat.clear (Join-Path $session.evidence "$($chat.stage).png") $canvas $desktop
        Assert-That ($null -ne $clear) "Unread message $($chat.clear) is not painted in $($chat.name)"
        Assert-That ($clear.blue_below -eq 0) "Read mark drawn under the unread $($chat.clear) in $($chat.name): blue=$($clear.blue_below)"
    }
    Hub-Pass $session "$($chat.stage)=$($chat.shown) blue=$($mark.blue_below)"
}
