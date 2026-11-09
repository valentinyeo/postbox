$chats = @(
    @{ name = 'Verification Read'; id = 'ticks-read@s.whatsapp.net'; shown = $true; stage = 'ticks-read' },
    @{ name = 'Verification Sent'; id = 'ticks-sent@s.whatsapp.net'; shown = $false; stage = 'ticks-sent' },
    @{ name = 'Verification Group'; id = 'ticks-group@g.us'; shown = $false; stage = 'ticks-group' },
    @{ name = 'Verification Slack'; id = 'slack:fixture-ticks:channel'; shown = $false; stage = 'ticks-slack' }
)
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
    Save-Screen $session $chat.stage
    Hub-Pass $session "$($chat.stage)=$($chat.shown)"
}
