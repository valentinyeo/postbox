$preferences = "HKCU:\Software\MessagesVerification\$($session.id)\Software\Messages"
$selectedId = (Read-Control $session status).selected.id
$pinnedIds = {
    $stored = (Get-ItemProperty -Path $preferences -Name PinnedChats -ErrorAction SilentlyContinue).PinnedChats
    @(if ($stored) { $stored -split "`n" | Where-Object { $_ } | ForEach-Object { ($_ -split "`t")[2] } })
}
Invoke-PaletteCommand $session 'Pin chat to top'
$null = Wait-Until { $ids = @(& $pinnedIds); $ids.Count -eq 1 -and $ids[0] -ceq $selectedId } 'selected chat saved as the only pinned chat'
Invoke-PaletteCommand $session 'Unpin selected chat'
$null = Wait-Until { @(& $pinnedIds).Count -eq 0 } 'selected chat unpinned'
Send-Keys $session '^{TAB}'
$null = Wait-Until { (Read-Control $session status).selected.name -eq 'Verification Beta' } 'next chat'
Save-Screen $session after
Send-Keys $session '^+{TAB}'
$null = Wait-Until { (Read-Control $session status).selected.name -eq 'Verification Alpha' } 'previous chat'
