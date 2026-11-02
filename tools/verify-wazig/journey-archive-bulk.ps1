$compose.SetFocus()
Assert-That ($compose.Current.HasKeyboardFocus -and (Read-Edit $compose) -eq '') 'bulk: composer did not start focused and empty'
Save-Screen $session before
Send-Keys $session '^a'
$null = Wait-Until {
    (Read-Control $session status).bulk_selected_count -eq 2
} 'bulk: Ctrl+A in empty composer selected no chats'
Save-Screen $session selected
Assert-That $compose.Current.HasKeyboardFocus 'bulk: selection moved focus out of composer'
$firstName = @((Read-Control $session chats).chats)[0].name
Invoke-PaletteCommand $session $firstName
$null = Wait-Until { (Read-Control $session status).bulk_selected_count -eq 0 } 'bulk: palette pick left the multi-select on'
Save-Screen $session palette-cleared-selection
Send-Keys $session '^a'
$null = Wait-Until { (Read-Control $session status).bulk_selected_count -eq 2 } 'bulk: Ctrl+A did not select both chats again'
Send-Keys $session '^e'
$null = Wait-Until {
    $state = Read-Control $session status
    $rows = @((Get-Content $provider -Raw | ConvertFrom-Json).data)
    $inbox = @((Read-Control $session chats).chats)
    $state.pending_archives -eq 0 -and $rows.Count -eq 2 -and
        @($rows | Where-Object { $_.archived -eq $true }).Count -eq 2 -and
        $state.chat_count -eq 0 -and $inbox.Count -eq 0
} 'bulk: Ctrl+E did not archive every selected chat'
Save-Screen $session after
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until { $compose.Current.IsEnabled } 'bulk: archived composer unavailable for text check'
$compose.SetFocus()
Send-Keys $session 'hello'
$null = Wait-Until { (Read-Edit $compose) -ceq 'hello' } 'bulk: composer did not receive text'
Send-Keys $session '^a'
$null = Wait-Until {
    $pattern = $compose.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
    $selection = @($pattern.GetSelection())
    $selection.Count -eq 1 -and $selection[0].GetText(-1) -ceq 'hello' -and
        (Read-Control $session status).bulk_selected_count -eq 0
} 'bulk: Ctrl+A with text did not keep text select-all'
Save-Screen $session text-selected
Send-Keys $session '{BACKSPACE}'
$null = Wait-Until { (Read-Edit $compose) -eq '' } 'bulk: composer did not clear'
$pickChats = $null
try { $pickChats = @((Read-Control $session chats).chats) } catch { }
if ($pickChats -and $pickChats.Count -ge 5) {
    Invoke-PaletteCommand $session 'Show combined inbox'
    $null = Wait-Until { (Read-Control $session chats).chats.Count -ge 5 } 'bulk pick: not enough chats'
    $list = Get-Edit (Get-Window $session) '1016'
    $handle = [IntPtr]$list.Current.NativeWindowHandle
    $origin = [VerifyWindow+Point]::new()
    Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'bulk pick: cannot locate chat list'
    $rowHeight = [UIntPtr]::Zero
    $topIndex = [UIntPtr]::Zero
    Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x01A1, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$rowHeight) -ne [IntPtr]::Zero) 'bulk pick: cannot read row height'
    Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x018E, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$topIndex) -ne [IntPtr]::Zero) 'bulk pick: cannot read top row'
    function Get-ChatRowPoint([int]$Row) {
        $point = [VerifyWindow+Point]::new()
        $point.X = $origin.X + 40
        $point.Y = $origin.Y + [int]((($Row - [int]$topIndex.ToUInt64()) * $rowHeight.ToUInt64()) + [Math]::Floor($rowHeight.ToUInt64() / 2))
        return $point
    }
    $first = Get-ChatRowPoint 0
    [VerifyMenus]::Click($session.pid, $first.X, $first.Y, $false)
    $null = Wait-Until { (Read-Control $session status).selected.name } 'bulk pick: first chat not selected'
    for ($row = 1; $row -lt 5; $row++) {
        $point = Get-ChatRowPoint $row
        [VerifyMenus]::ClickWith($session.pid, $point.X, $point.Y, $true, $false)
        $null = Wait-Until { (Read-Control $session status).bulk_selected_count -eq ($row + 1) } "bulk pick: Ctrl+click row $row" 10
    }
    Save-Screen $session ctrl-picked
    Assert-That ((Read-Control $session status).selected.name) 'bulk pick: Ctrl+click dropped the open chat'
    Send-Keys $session '{ESC}'
    $null = Wait-Until { (Read-Control $session status).bulk_selected_count -eq 0 } 'bulk pick: Esc did not clear the selection' 10
    $first = Get-ChatRowPoint 0
    [VerifyMenus]::Click($session.pid, $first.X, $first.Y, $false)
    $null = Wait-Until { (Read-Control $session status).selected.name } 'bulk range: first chat not selected'
    $last = Get-ChatRowPoint 4
    [VerifyMenus]::ClickWith($session.pid, $last.X, $last.Y, $false, $true)
    $null = Wait-Until { (Read-Control $session status).bulk_selected_count -eq 5 } 'bulk range: Shift+click selected the wrong count' 10
    Save-Screen $session shift-picked
    Send-Keys $session '{ESC}'
    $null = Wait-Until { (Read-Control $session status).bulk_selected_count -eq 0 } 'bulk range: Esc did not clear the range' 10
    Hub-Pass $session ctrl-shift-chat-pick
}
