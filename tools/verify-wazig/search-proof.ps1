function Find-SidebarSearch($Session) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, '1008')
    return (Get-Window $Session).FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
}

function Read-SearchSample($Session, [string]$Query, [string]$Shortcut, [bool]$Baseline) {
    (Get-Edit (Get-Window $Session) '1016').SetFocus()
    Send-Keys $Session $Shortcut
    $palette = $null
    if ($Baseline) {
        $edit = Find-SidebarSearch $Session
    } else {
        $palette = Get-PaletteWindow $Session
        $edit = Get-Edit $palette '1064'
    }
    Send-Keys $Session '^a'
    Send-Keys $Session $Query
    $settled = @{ signature = ''; since = [DateTime]::UtcNow; sample = $null }
    $null = Wait-Until {
        if ((Read-Edit $edit) -cne $Query -or -not $edit.Current.HasKeyboardFocus) { return $false }
        $state = Read-Control $Session status
        if ($state.search -cne $Query) { return $false }
        $arguments = if ($state.show_archived) { @('--archived') } else { @() }
        $rows = @((Read-Control $Session chats -Arguments $arguments).chats)
        $list = if ($Baseline) { Get-Edit (Get-Window $Session) '1016' } else { Get-Edit $palette '1072' }
        $labels = [string[]]@(if ($Baseline) { $rows | ForEach-Object name } else { Read-ListLabels $list })
        $sample = @{
            query = Read-Edit $edit; shortcut = $Shortcut; focused = $edit.Current.HasKeyboardFocus
            edit_id = $edit.Current.AutomationId; palette = (-not $Baseline); state = $state
            identities = @($rows | ForEach-Object { "$($_.provider)|$($_.account)|$($_.id)" })
            rows = $rows; labels = $labels; native_count = Read-ListCount $list
        }
        $signature = ConvertTo-Json -InputObject @($sample.identities, $labels, $sample.native_count) -Depth 8 -Compress
        if ($signature -cne $settled.signature) {
            $settled.signature = $signature; $settled.since = [DateTime]::UtcNow; $settled.sample = $sample
            return $false
        }
        return ([DateTime]::UtcNow - $settled.since).TotalMilliseconds -ge 600
    } "settled typed search $Query through $Shortcut"
    return $settled.sample
}

function Assert-PaletteSearchShortcuts($Session) {
    Assert-That ($null -eq (Find-SidebarSearch $Session)) 'Sidebar search edit 1008 remains'
    $proof = @()
    foreach ($shortcut in @('^f', '/')) {
        $proof += Read-SearchSample $Session 'Beta' $shortcut $false
        Send-Keys $Session '{ESC}'
        $null = Wait-Until { (Read-Control $Session status).search -ceq '' } 'Escape clears palette search'
    }
    $proof | ConvertTo-Json -Depth 14 | Set-Content (Join-Path $Session.evidence 'search-shortcuts.json')
}

function Save-PaletteArchiveInk($Session) {
    $views = @((Read-Control $Session status).view_order)
    $index = 0
    while ($index -lt $views.Count -and -not ($views[$index].provider -eq 'whatsapp' -and $views[$index].account -eq 'personal')) { $index++ }
    Assert-That ($index -lt 8 -and $index -lt $views.Count) 'Personal fixture account missing'
    Send-Keys $Session "^$($index + 2)"
    $null = Wait-Until { (Read-Control $Session status).current_view.account -ceq 'personal' } 'personal search account'
    if (-not (Read-Control $Session status).include_archived) { Invoke-PaletteCommand $Session 'Toggle archived chats in this view' }
    $sample = Read-SearchSample $Session 'Verification' '^f' $false
    $palette = Get-PaletteWindow $Session
    $list = Get-Edit $palette '1072'
    $bounds = $list.Current.BoundingRectangle
    $desktop = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $rowHeight = [UIntPtr]::Zero
    Assert-That ([VerifyWindow]::ReadListMetric([IntPtr]$list.Current.NativeWindowHandle, 0x01A1, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$rowHeight) -ne [IntPtr]::Zero) 'Cannot read palette row height'
    @{ sample = $sample; x = [int]($bounds.Left - $desktop.Left); y = [int]($bounds.Top - $desktop.Top); width = [int]$bounds.Width; height = [int]$bounds.Height; row_height = $rowHeight.ToUInt64() } |
        ConvertTo-Json -Depth 14 | Set-Content (Join-Path $Session.evidence 'search-archive.json')
    Save-Screen $Session search-archive
    Send-Keys $Session '{ESC}'
    Invoke-PaletteCommand $Session 'Toggle archived chats in this view'
    Send-Keys $Session '%i'
}
function Save-SearchGroups($Session, $Sample) {
    $list = Get-Edit (Get-PaletteWindow $Session) '1072'
    $bounds = $list.Current.BoundingRectangle
    $desktop = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $height = [UIntPtr]::Zero
    $top = [UIntPtr]::Zero
    $handle = [IntPtr]$list.Current.NativeWindowHandle
    Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x01A1, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$height) -ne [IntPtr]::Zero) 'Cannot read group row height'
    Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x018E, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$top) -ne [IntPtr]::Zero -and $top.ToUInt64() -eq 0) 'Grouped results are scrolled out of view'
    @{ sample = $Sample; x = [int]($bounds.Left - $desktop.Left); y = [int]($bounds.Top - $desktop.Top); width = [int]$bounds.Width; height = [int]$bounds.Height; row_height = $height.ToUInt64() } |
        ConvertTo-Json -Depth 14 | Set-Content (Join-Path $Session.evidence 'search-groups.json')
    Save-Screen $Session search-groups
}
