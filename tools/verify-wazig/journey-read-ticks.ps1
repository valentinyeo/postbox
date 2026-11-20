$chats = @(
    @{ name = 'Verification Read'; id = 'ticks-read@s.whatsapp.net'; shown = $true; stage = 'ticks-read' },
    @{ name = 'Verification Sent'; id = 'ticks-sent@s.whatsapp.net'; shown = $false; stage = 'ticks-sent' },
    @{ name = 'Verification Group'; id = 'ticks-group@g.us'; shown = $false; stage = 'ticks-group' },
    @{ name = 'Verification Slack'; id = 'slack:fixture-ticks:channel'; shown = $false; stage = 'ticks-slack' },
    @{ name = 'Verification Signal Contact'; id = 'signal:ticks-contact'; shown = $true; stage = 'ticks-signal' },
    @{ name = 'Verification Signal Crowd'; id = 'signal:group:ticks-group'; shown = $false; stage = 'ticks-signal-group' },
    @{ name = 'Verification Telegram Contact'; id = 'telegram:user:ticks-contact'; shown = $true; stage = 'ticks-telegram' },
    @{ name = 'Verification Telegram Fresh'; id = 'telegram:user:ticks-unread'; shown = $false; stage = 'ticks-telegram-unread' }
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
foreach ($chat in $chats) {
    Send-Keys $session '^f'
    Send-Keys $session $chat.name
    $null = Wait-Until {
        $state = Read-Control $session status
        $shown = Read-Control $session messages
        $own = @($shown.messages | Where-Object { $_.id -eq 'tick-own' -and $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[3] -gt $_.bubble[1] })
        $shown.chat.id -eq $chat.id -and $own.Count -eq 1 -and $state.read_tick.message -eq 'tick-own'
    } "newest own message painted in $($chat.name)"
    $state = Read-Control $session status
    Assert-That ($state.read_tick.shown -eq $chat.shown) "Read tick wrong in $($chat.name): shown=$($state.read_tick.shown) expected=$($chat.shown)"
    $state.read_tick | ConvertTo-Json | Set-Content (Join-Path $session.evidence "$($chat.stage).json")
    $shown = Read-Control $session messages
    $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence "$($chat.stage).messages.json")
    Save-Screen $session $chat.stage
    $own = @($shown.messages | Where-Object { $_.id -eq 'tick-own' })[0]
    $band = Get-ReadMarkBand $own.bubble $canvas $desktop
    $blue = Measure-ReadMark (Join-Path $session.evidence "$($chat.stage).png") $band.left $band.top $band.right $band.bottom
    @{ bubble = @($own.bubble); blue_below = $blue } | ConvertTo-Json | Set-Content (Join-Path $session.evidence "$($chat.stage).mark.json")
    if ($chat.shown) {
        Assert-That ($blue -ge 6) "Read mark missing under the newest own bubble in $($chat.name): blue=$blue"
    } else {
        Assert-That ($blue -eq 0) "Read mark drawn under the newest own bubble in $($chat.name) although it shows none: blue=$blue"
    }
    Hub-Pass $session "$($chat.stage)=$($chat.shown) blue=$blue"
}
