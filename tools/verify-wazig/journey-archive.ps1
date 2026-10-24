Assert-That ((Read-Control $session status).selected.name -eq 'Verification Alpha') 'Archive fixture did not start on Alpha'
Send-Keys $session '^e'
$null = Wait-Until {
    $state = Read-Control $session status
    $row = (Get-Content $provider -Raw | ConvertFrom-Json).data | Where-Object name -eq 'Verification Alpha'
    $row.archived -and $state.pending_archives -eq 0 -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Beta'
} 'Alpha archived through Ctrl+E'
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until { $state = Read-Control $session status; $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Alpha' } 'Alpha in Archive'
Invoke-PaletteCommand $session 'Show inbox chats' action
$null = Wait-Until { -not (Read-Control $session status).show_archived } 'inbox after archive snapshot'
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until { (Read-Control $session status).show_archived } 'Archive before persisted snapshot'
$keep = Join-Path $messages 'archive-state.txt'
$null = Wait-Until {
    (Read-Control $session status).pending_archives -eq 0 -and (Get-Content $keep -Raw).Contains("verify-alpha@s.whatsapp.net`t0`t")
} 'Plain archive state persisted'
Copy-Item $keep (Join-Path $Evidence 'kept-archive-state.txt')
Save-Screen $session kept
Invoke-PaletteCommand $session 'Show inbox chats'
$null = Wait-Until { $state = Read-Control $session status; -not $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Beta' } 'inbox before incoming delivery'
$incoming = Get-Content $provider -Raw | ConvertFrom-Json
$alpha = $incoming.data | Where-Object name -eq 'Verification Alpha'
Assert-That ($alpha.archived -and $alpha.unread_count -eq 0) 'Unexpected pre-delivery provider state'
$alpha.archived = $true
$alpha.unread = $true
$alpha.unread_count = 1
$alpha.last_message_ts = '2026-10-10T11:00:00Z'
$incoming.messages | Add-Member -NotePropertyName 'verify-alpha@s.whatsapp.net' -NotePropertyValue @{ data = @{ messages = @(
    @{ MsgID = 'verify-incoming-1'; ChatJID = 'verify-alpha@s.whatsapp.net'; FromMe = $false; SenderName = 'Verification Alpha'; Text = 'Verification incoming message'; Timestamp = $alpha.last_message_ts }
) } }
$incoming | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'incoming-provider.json')
Copy-Item (Join-Path $Evidence 'incoming-provider.json') "$provider.next"
$null = Wait-Until {
    try { [IO.File]::Move("$provider.next", $provider, $true); return $true } catch [IO.IOException] { return $false }
} 'atomic incoming provider delivery'
Add-Content (Join-Path $Evidence 'actions.log') 'provider: incoming verify-incoming-1; archived=true; unread_count=1'
$null = Wait-Until {
    $row = (Get-Content $provider -Raw | ConvertFrom-Json).data | Where-Object name -eq 'Verification Alpha'
    $state = Read-Control $session status
    $row.archived -and $row.unread_count -eq 1 -and $state.pending_archives -eq 0 -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Beta'
} 'incoming delivery leaves Alpha archived'
Save-Screen $session inbox
$chats = Read-Control $session chats
Assert-That ($chats.total -eq 1 -and $chats.chats[0].name -eq 'Verification Beta') 'Alpha resurfaced in the main list'
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until {
    $state = Read-Control $session status
    $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Alpha' -and $state.selected.archived -and $state.selected.unread -and $state.selected.unread_count -eq 1
} 'Alpha remains in Archive with updated unread count'
Save-Screen $session after
