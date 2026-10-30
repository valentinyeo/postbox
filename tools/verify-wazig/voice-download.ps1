function Invoke-VoiceDownloadJourney($Session) {
    $headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session 'Synthetic queued voice download check'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { (Read-Control $Session status).pending_sends -gt 0 -and @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.status -eq 503 }).Count -gt 0 } 'send remains queued after provider failure'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/voice-new" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
    Invoke-PaletteCommand $Session 'Refresh'
    $null = Wait-Until {
        $rows = @(Read-VoiceMessages $Session | Where-Object { $_.id -like 'NEW-VOICE-*' })
        @($rows | Where-Object { $_.id -ne 'NEW-VOICE-4' -and $_.local }).Count -eq 3 -and`n            @($rows | Where-Object { $_.id -eq 'NEW-VOICE-4' -and $_.download_state -eq 'retry' }).Count -eq 1
    } 'new voice downloads despite queued send' -Seconds 10
    $elapsed = $clock.ElapsedMilliseconds
    $rows = @(Read-VoiceMessages $Session | Where-Object { $_.id -like 'NEW-VOICE-*' })
    $failed = @($rows | Where-Object id -eq 'NEW-VOICE-4')[0]
    Assert-That ($failed.download_state -eq 'retry' -and -not $failed.local) 'failed voice offers Tap to retry'
    $proof = [ordered]@{ elapsed_ms = $elapsed; pending_sends = (Read-Control $Session status).pending_sends; downloaded = @($rows | Where-Object id -ne 'NEW-VOICE-4'); failed = $failed }
    Save-Screen $Session 'voice-download-failed'
    Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/voice-retry" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
    $handle = Get-VoiceCanvas $Session
    $bounds = [VerifyVoice]::Bounds($Session.pid, $handle)
    $x = $bounds.Left + [int](($failed.media[0] + $failed.media[2]) / 2)
    $y = $bounds.Top + [int](($failed.media[1] + $failed.media[3]) / 2)
    [VerifyMenus]::Click($Session.pid, $x, $y, $false)
    Add-Content (Join-Path $Session.evidence 'actions.log') 'SendInput: Tap to retry NEW-VOICE-4'
    $null = Wait-Until { @(Read-VoiceMessages $Session | Where-Object { $_.id -eq 'NEW-VOICE-4' -and $_.local }).Count -eq 1 } 'failed voice downloaded after retry' -Seconds 10
    $proof.retried = @(Read-VoiceMessages $Session | Where-Object id -eq 'NEW-VOICE-4')[0]
    Save-Screen $Session 'voice-download-retried'
    $target = $proof.retried
    $dpi = [int][VerifyWindow]::GetDpiForWindow($handle)
    $x = $bounds.Left + $target.media[0] + [int](18 * $dpi / 96)
    $y = $bounds.Top + [int](($target.media[1] + $target.media[3]) / 2)
    [VerifyMenus]::Click($Session.pid, $x, $y, $false)
    Add-Content (Join-Path $Session.evidence 'actions.log') 'SendInput: play downloaded NEW-VOICE-4'
    $null = Wait-Until { @(Read-VoiceMessages $Session | Where-Object { $_.id -eq 'NEW-VOICE-4' -and $_.playing -and $_.position_ms -gt 0 }).Count -eq 1 } 'downloaded voice playback advances'
    $proof.playing = @(Read-VoiceMessages $Session | Where-Object id -eq 'NEW-VOICE-4')[0]
    Save-Screen $Session 'voice-download-playing'
    $proof | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'voice-download.json')
    Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/voice-send-ready" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
    $null = Wait-Until { (Read-Control $Session status).pending_sends -eq 0 } 'fixture queued send acknowledged' -Seconds 90
}
