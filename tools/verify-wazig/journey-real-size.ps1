. "$PSScriptRoot/search-proof.ps1"
Add-Type -Path "$PSScriptRoot/voice.cs"
$seed = Invoke-RestMethod "$($session.bridge_url)/fixture/seed" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' }
$seed | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'seed.json')
$counts = $seed.counts
Write-Output "seeded_chats=$($counts.chats) seeded_messages=$($counts.messages) seeded_voice=$($counts.voice) seeded_images=$($counts.images) seeded_groups=$($counts.groups)"
Assert-That ($counts.chats -ge 300 -and $counts.messages -ge 6000 -and $counts.voice -ge 50 -and $counts.images -ge 100 -and $counts.groups -ge 30) 'Real-size seed shrank below its required size'
$state = Read-Control $session status
$list = Get-Edit (Get-Window $session) '1016'
Assert-That ($state.chat_count -eq $seed.inbox -and (Read-ListCount $list) -eq $seed.inbox) 'Real-size inbox count differs from seed'
Read-Control $session chats | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'inbox.chats.json')
Write-Output "app_inbox_chats=$($state.chat_count)"
Write-Output 'step=inbox finished=true'
Send-Keys $session '^+{END}'
$null = Wait-Until { (Read-Control $session status).selected.id -ne $seed.busy } 'last inbox chat selected'
$top = [UIntPtr]::Zero
Assert-That ([VerifyWindow]::ReadListMetric([IntPtr]$list.Current.NativeWindowHandle, 0x018E, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$top) -ne [IntPtr]::Zero -and $top.ToUInt64() -gt 0) 'Real-size chat list did not scroll'
@{ top_index = $top.ToUInt64(); native_count = Read-ListCount $list; state = Read-Control $session status } |
    ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'list-scroll.json')
Save-Screen $session list-scrolled
Write-Output 'step=list-scroll finished=true'
Send-Keys $session '^+{HOME}'
$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.chat.id -eq $seed.busy -and $shown.messages.Count -eq 80
} 'real-size busiest chat loads its latest 80 messages'
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'busy.messages.json')
Save-Screen $session busy
Write-Output 'step=busy finished=true'
$canvas = Get-Edit (Get-Window $session) '1024'
$bounds = $canvas.Current.BoundingRectangle
$null = Wait-Until {
    [VerifyVoice]::Wheel($session.pid, [int]($bounds.Left + $bounds.Width / 2), [int]($bounds.Top + $bounds.Height / 2), 32760)
    $shown = Read-Control $session messages
    $first = @($shown.messages)[0]
    $shown.chat.id -eq $seed.busy -and $shown.messages.Count -eq 1000 -and
        $first.bubble[2] -gt $first.bubble[0] -and $first.bubble[3] -gt $first.bubble[1]
} 'real-size busiest chat scrolls to the loaded history top' 120
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'busy-top.messages.json')
Save-Screen $session busy-top
Write-Output 'step=busy-top finished=true'
$sample = Read-SearchSample $session $seed.search '^f' $false
$sample | ConvertTo-Json -Depth 14 | Set-Content (Join-Path $session.evidence 'search.json')
Assert-That ($sample.rows.Count -eq $seed.search_count -and $sample.rows.Count -ge 50) 'Real-size search lost matching chats'
Save-Screen $session search
Send-Keys $session '{ESC}'
$null = Wait-Until { (Read-Control $session status).search -ceq '' } 'real-size search clears'
Write-Output 'step=search finished=true'
$null = Read-SearchSample $session 'Orchard Voice' '^f' $false
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.chat.id -eq $seed.voice -and @($shown.messages | Where-Object { $_.media_type -eq 'audio' -and $_.local }).Count -ge 1 -and
        @($shown.messages | Where-Object { $_.media_type -eq 'image' -and $_.local }).Count -ge 2
} 'real-size voice chat opens and media downloads' 60
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'voice.messages.json')
Save-Screen $session voice
Write-Output 'step=voice finished=true'
$null = Read-SearchSample $session 'Orchard Group 272' '^f' $false
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.chat.id -eq $seed.group -and $shown.messages.Count -eq 16 -and
        @($shown.messages | Where-Object { -not $_.from_me -and $_.sender -like 'Seed Sender*' }).Count -gt 0
} 'real-size group opens with sender names'
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'group.messages.json')
Save-Screen $session group
Write-Output 'step=group finished=true'
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until { $state = Read-Control $session status; $state.show_archived -and $state.chat_count -eq $seed.archived } 'real-size archived view count'
Read-Control $session chats -Arguments @('--archived') | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'archived.chats.json')
Write-Output "app_archived_chats=$((Read-Control $session status).chat_count)"
Save-Screen $session archived
Write-Output 'step=archived finished=true'
Invoke-PaletteCommand $session 'Show inbox chats'
$null = Wait-Until { $state = Read-Control $session status; -not $state.show_archived -and $state.chat_count -eq $seed.inbox } 'real-size returns to inbox'
Read-Control $session chats | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'after.chats.json')
Save-Screen $session after
Write-Output 'step=inbox-return finished=true'
Read-BridgeRequests $session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'real-size.requests.json')
