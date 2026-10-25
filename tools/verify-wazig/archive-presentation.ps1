function Read-ArchivePaletteState($Session, [bool]$Enabled, [string]$Name, [bool]$Activate = $false) {
    Send-Keys $Session '^k'
    $palette = Get-PaletteWindow $Session
    $edit = Get-Edit $palette '1064'
    $list = Get-Edit $palette '1072'
    Send-Keys $Session 'archive'
    $null = Wait-Until { (Read-Edit $edit) -ceq 'archive' } 'archive query'
    $expected = 'Toggle archived chats in this view: ' + $(if ($Enabled) { 'On' } else { 'Off' })
    $labels = @(Read-ListLabels $list)
    $index = [Array]::IndexOf($labels, $expected)
    Assert-That ($index -ge 0 -and $index -lt 10 -and @($labels | Where-Object { $_ -ceq $expected }).Count -eq 1) "Missing visible palette state: $expected"
    @{ enabled = $Enabled; query = 'archive'; expected = $expected; labels = $labels; index = $index; activated = $Activate } |
        ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session.evidence "$Name.palette.json")
    Save-Screen $Session $Name
    if ($Activate) {
        for ($step = 0; $step -lt $index; $step++) { Send-Keys $Session '{DOWN}' }
        Send-Keys $Session '{ENTER}'
        $null = Wait-Until { (Read-Control $Session status).include_archived -ne $Enabled } 'palette flips drawing switch'
    } else {
        Send-Keys $Session '{ESC}'
    }
}

function Save-ArchivePresentationScene($Session, [string]$Name, [string]$Mode) {
    $window = Get-Window $Session
    $list = Get-Edit $window '1016'
    $handle = [IntPtr]$list.Current.NativeWindowHandle
    $origin = [VerifyWindow+Point]::new()
    $client = [VerifyWindow+Rect]::new()
    Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'Cannot locate chat list'
    Assert-That ([VerifyWindow]::GetClientRect($handle, [ref]$client)) 'Cannot read chat list size'
    $rowHeight = [UIntPtr]::Zero
    $topIndex = [UIntPtr]::Zero
    Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x01A1, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$rowHeight) -ne [IntPtr]::Zero) 'Cannot read row height'
    Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x018E, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$topIndex) -ne [IntPtr]::Zero) 'Cannot read top row'
    $desktop = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $rows = @((Read-Control $Session chats).chats)
    $state = Read-Control $Session status
    $theme = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../src/theme.zig'))
    $weight = [regex]::Match($theme, 'pub const archived_row_foreground_weight: u8 = (\d+);')
    Assert-That ($weight.Success) 'Missing archived row foreground mix weight'
    $layout = @{
        dpi = [VerifyWindow]::GetDpiForWindow($handle); row_height = $rowHeight.ToUInt64(); top = $topIndex.ToUInt64()
        x = $origin.X - $desktop.Left; y = $origin.Y - $desktop.Top; width = $client.Right; height = $client.Bottom
        mode = $Mode; rows = $rows; selected = $state.selected.id
        colour_model = 'theme-foreground-mix'; foreground_weight = [int]$weight.Groups[1].Value
    }
    $layout | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.layout.json")
    $null = Wait-Until {
        Save-Screen $Session $Name
        & python "$PSScriptRoot/check-archive-presentation.py" $Session.evidence --scene $Name | Out-Host
        $LASTEXITCODE -eq 0
    } "measured colour-mixed archive row $Name"
}

function Assert-ArchiveFooterRemoved($Session) {
    Add-Type -Path "$PSScriptRoot/menus.cs"
    $window = Get-Window $Session
    $missing = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, '1146')
    Assert-That ($null -eq $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $missing)) 'Former Show archived control still exists'
    $handle = [IntPtr]$window.Current.NativeWindowHandle
    $client = [VerifyWindow+Rect]::new()
    $origin = [VerifyWindow+Point]::new()
    Assert-That ([VerifyWindow]::GetClientRect($handle, [ref]$client)) 'Cannot read app bounds'
    Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'Cannot locate app client'
    $dpi = [VerifyWindow]::GetDpiForWindow($handle)
    $scale = $dpi / 96.0
    $leftWidth = [Math]::Clamp([Math]::Truncate($client.Right / 3), [Math]::Round(280 * $scale), [Math]::Round(390 * $scale))
    $x = [int]($origin.X + $leftWidth - [Math]::Round(82 * $scale))
    $y = [int]($origin.Y + $client.Bottom - [Math]::Round(13 * $scale))
    $before = Read-Control $Session status
    $rows = @((Read-Control $Session chats).chats)
    [VerifyMenus]::Click($Session.pid, $x, $y, $false)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $null = Wait-Until {
        $after = Read-Control $Session status
        Assert-That ($after.include_archived -eq $before.include_archived -and $after.chat_count -eq $before.chat_count -and $after.pending_archives -eq 0) 'Former footer click changed the app'
        $clock.ElapsedMilliseconds -ge 1000
    } 'former footer click remains inert'
    $desktop = [System.Windows.Forms.SystemInformation]::VirtualScreen
    @{
        point = @($x, $y); before = $before; after = (Read-Control $Session status); rows = $rows
        rect = @([int]($origin.X + $leftWidth - 150 * $scale - $desktop.Left), [int]($origin.Y + $client.Bottom - 26 * $scale - $desktop.Top), [int]($origin.X + $leftWidth - 12 * $scale - $desktop.Left), [int]($origin.Y + $client.Bottom - $desktop.Top))
    } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'archive-footer.json')
    Save-Screen $Session archive-footer
}

function Invoke-ArchivePresentation($Session) {
    Send-Keys $Session '%1'
    $null = Wait-Until { -not (Read-Control $Session status).current_view.inbox } 'presentation account'
    if (-not (Read-Control $Session status).include_archived) { Invoke-PaletteCommand $Session 'Toggle archived chats in this view' }
    $identities = @((Read-Control $Session chats).chats | ForEach-Object { "$($_.provider)|$($_.account)|$($_.id)|$($_.archived)" } | Sort-Object)
    Read-ArchivePaletteState $Session $true archive-palette-on $true
    Read-ArchivePaletteState $Session $false archive-palette-off $true
    Read-ArchivePaletteState $Session $true archive-palette-restored
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 4 } 'archive rows restored'
    $restored = @((Read-Control $Session chats).chats | ForEach-Object { "$($_.provider)|$($_.account)|$($_.id)|$($_.archived)" } | Sort-Object)
    Assert-That (($identities -join "`n") -ceq ($restored -join "`n")) 'Drawing toggle changed archived identities'
    @{ before = $identities; after = $restored } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'archive-identities.json')
    foreach ($scope in @('sidebar', 'search', 'inbox')) {
        if ($scope -eq 'search') {
            Send-Keys $Session '^f'
            Send-Keys $Session 'row'
            $null = Wait-Until { (Read-Control $Session status).search -ceq 'row' } 'search rows'
        }
        if ($scope -eq 'inbox') {
            Send-Keys $Session '^f'
            Send-Keys $Session '^a{BACKSPACE}'
            Send-Keys $Session '%i'
        }
        Send-Keys $Session '^1'
        $null = Wait-Until { -not (Read-Control $Session status).selected.archived } 'live control selected'
        $list = Get-Edit (Get-Window $Session) '1016'
        $bounds = $list.Current.BoundingRectangle
        $rows = @((Read-Control $Session chats).chats)
        $archived = @($rows | Where-Object archived)[0]
        $index = [Array]::IndexOf(@($rows.id), $archived.id)
        $height = [int][Math]::Round(64 * [VerifyWindow]::GetDpiForWindow([IntPtr]$list.Current.NativeWindowHandle) / 96.0)
        $x = [int]($bounds.Left + 75)
        $y = [int]($bounds.Top + $index * $height + $height / 2)
        Assert-That ($index -ge 0 -and $y -lt $bounds.Bottom) 'Archived probe is not visible'
        $canvas = (Get-Edit (Get-Window $Session) '1024').Current.BoundingRectangle
        [VerifyMenus]::Hover($Session.pid, [int]($canvas.Left + 10), [int]($canvas.Top + 10))
        Save-ArchivePresentationScene $Session "archive-$scope-dim" dim
        [VerifyMenus]::Hover($Session.pid, $x, $y)
        Save-ArchivePresentationScene $Session "archive-$scope-hover" hover
        [VerifyMenus]::Click($Session.pid, $x, $y, $false)
        $null = Wait-Until { (Read-Control $Session status).selected.id -ceq $archived.id } 'archived row selected'
        [VerifyMenus]::Hover($Session.pid, [int]($canvas.Left + 10), [int]($canvas.Top + 10))
        Save-ArchivePresentationScene $Session "archive-$scope-selected" selected
    }
    Send-Keys $Session '%1'
}
