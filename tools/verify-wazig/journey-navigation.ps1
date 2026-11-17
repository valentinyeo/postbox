$preferences = "HKCU:\Software\MessagesVerification\$($session.id)\Software\Messages"
$selectedId = (Read-Control $session status).selected.id
Invoke-PaletteCommand $session 'Pin chat to top'
$null = Wait-Until { (Get-ItemProperty -Path $preferences -Name PinnedChats -ErrorAction SilentlyContinue).PinnedChats -like "*$selectedId*" } 'selected chat saved as pinned'
Invoke-PaletteCommand $session 'Unpin selected chat'
$null = Wait-Until { (Get-ItemProperty -Path $preferences -Name PinnedChats -ErrorAction SilentlyContinue).PinnedChats -notlike "*$selectedId*" } 'selected chat unpinned'
Send-Keys $session '^{TAB}'
$null = Wait-Until { (Read-Control $session status).selected.name -eq 'Verification Beta' } 'next chat'
Save-Screen $session after
Send-Keys $session '^+{TAB}'
$null = Wait-Until { (Read-Control $session status).selected.name -eq 'Verification Alpha' } 'previous chat'
