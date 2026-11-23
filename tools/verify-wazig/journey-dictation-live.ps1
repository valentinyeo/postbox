function Live-Composer {
    return Get-Edit (Get-Window $session) '1032'
}

function Live-Snapshot([string]$Name, [string]$Expected, [string]$Phase) {
    $observed = Wait-Until {
        $text = Read-Edit (Live-Composer)
        $state = Read-Control $session status
        if ($text -ceq $Expected -and $state.dictation.phase -ceq $Phase) {
            @{ text = $text; state = $state; pid = $session.pid; start_ticks = $session.startTicks;
               sha256 = $session.sha256; commit = $session.commit }
        }
    } "$Name composer and phase" 30
    Assert-That ($observed.state.dictation.microphone_entries -eq 0 -and $observed.state.dictation.transcription_attempts -eq 0) 'Live fixture reached a real microphone or batch upload'
    $observed | ConvertTo-Json -Depth 16 | Set-Content (Join-Path $session.evidence "$Name.live.json")
    Save-Screen $session $Name
    return $observed
}

Invoke-PaletteCommand $session 'Compose message'
$cases = @(
    @{ name = 'automatic'; label = 'Automatic'; first = 'hello'; revised = 'hello world'; final = 'Hello world.' },
    @{ name = 'english'; label = 'English'; first = 'hello'; revised = 'hello world'; final = 'Hello world.' },
    @{ name = 'german'; label = 'German'; first = ('Gr' + [char]0x00fc); revised = ('Gr' + [char]0x00fc + [char]0x00df + 'e aus'); final = ('Gr' + [char]0x00fc + [char]0x00df + 'e aus Berlin.') }
)
foreach ($case in $cases) {
    $null = Wait-Until { -not (Read-Control $session status).dictation.draining } 'previous live worker drained'
    Invoke-PaletteCommand $session "Dictation language: $($case.label)"
    Invoke-PaletteCommand $session 'Compose message'
    Send-Keys $session '^aBefore after^{HOME}{RIGHT 6}'
    $original = Read-Edit (Live-Composer)
    Assert-That ($original -ceq 'Before after') 'Original composer text missing'
    $before = Read-Control $session status
    Send-Keys $session '^d'
    $first = Live-Snapshot "$($case.name)-interim" "Before $($case.first) after" 'recording'
    Assert-That ($first.state.dictation.generation -eq $before.dictation.generation + 1 -and $first.state.dictation.consumed -eq $before.dictation.consumed) 'Interim was not shown by the active recording'
    $headers = @{ Authorization = "Bearer $($start.Environment['WAZIG_HUB_TOKEN'])" }
    $null = Invoke-RestMethod -Uri "$($bridge.url)/dictation-live/advance" -Headers $headers -TimeoutSec 10
    $revised = Live-Snapshot "$($case.name)-revised" "Before $($case.revised) after" 'recording'
    Assert-That ($revised.state.dictation.consumed -eq $before.dictation.consumed) 'Revision appeared only after completion'
    Send-Keys $session '^d'
    $final = Live-Snapshot "$($case.name)-final" "Before $($case.final) after" 'idle'
    Assert-That ($final.state.dictation.consumed -eq $before.dictation.consumed + 1) 'Final transcript was not consumed exactly once'
}
$requests = @(Read-BridgeRequests $session)
Assert-That (@($requests | Where-Object { $_.wire_path -eq '/v1/wazig/send' }).Count -eq 0) 'Live dictation sent a message'
Assert-That (@($requests | Where-Object { $_.kind -eq 'dictation-live' -and $_.stage -eq 'error' }).Count -eq 0) 'Fake Deepgram rejected the stream'
$requests | Where-Object { $_.kind -eq 'dictation-live' } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'dictation-live-wire.json')
