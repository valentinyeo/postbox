function Invoke-RepaintJourney($Session) {
    $null = Wait-Until {
        $state = Read-Control $Session status
        $shown = Read-Control $Session messages
        $state.selected.id -eq 'fixture-alpha' -and $shown.chat.id -eq 'fixture-alpha' -and $shown.messages.Count -eq 1
    } 'repaint selected baseline ready'
    $headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
    Save-Screen $Session before
    $beforeChats = Read-Control $Session chats
    $beforeChats | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'before.chats.json')
    $before = (Read-Control $Session status).paints
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/repaint/start" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
    $null = Wait-Until { $clock.Elapsed.TotalSeconds -ge 60 } '60 seconds without input' -Seconds 65
    $afterState = Read-Control $Session status
    $elapsed = $clock.Elapsed.TotalSeconds
    $after = $afterState.paints
    $delta = [ordered]@{}
    foreach ($field in @('window', 'window_full', 'canvas', 'canvas_full', 'list', 'list_full')) {
        Assert-That ($null -ne $before.$field -and $null -ne $after.$field) "Missing paint counter: $field"
        $delta[$field] = [long]$after.$field - [long]$before.$field
        Assert-That ($delta[$field] -ge 0) "Paint counter went backwards: $field"
    }
    $full = $delta.window_full + $delta.canvas_full + $delta.list_full
    $afterChats = Read-Control $Session chats
    $afterChats | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'after.chats.json')
    $provider = Invoke-RestMethod -Uri "$($Session.bridge_url)/fixture/repaint" -Headers $headers
    @{ before = $before; after = $after; delta = $delta; full = $full; elapsed_seconds = $elapsed; provider = $provider; selected_before = 'fixture-alpha'; selected_after = $afterState.selected.id } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'paints.json')
    Save-Screen $Session after
    $incoming = @($afterChats.chats | Where-Object { $_.id -eq 'fixture-beta' })
    $initial = @($beforeChats.chats | Where-Object { $_.id -eq 'fixture-beta' })
    Assert-That ($afterState.selected.id -eq 'fixture-alpha') 'Selected chat changed during repaint observation'
    Assert-That ($provider.ticks -ge 29 -and $provider.incoming -ge 5) 'Repaint provider did not send the workload'
    Assert-That ($incoming.Count -eq 1 -and $initial.Count -eq 1 -and $incoming[0].unread_count - $initial[0].unread_count -ge 5) 'Incoming messages did not reach the chat list'
    $list = Get-Edit (Get-Window $Session) '1016'
    $count = [UIntPtr]::Zero
    $ok = [VerifyWindow]::ReadListMetric([IntPtr]$list.Current.NativeWindowHandle, 0x18B, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$count)
    Assert-That ($ok -ne [IntPtr]::Zero -and $count.ToUInt64() -eq 2 -and $list.Current.BoundingRectangle.Height -gt 128) 'Incoming chat list rows are not visible'
    Assert-That ($full -le 3) "repaint: $full full repaints in 60 s, limit 3"
}
