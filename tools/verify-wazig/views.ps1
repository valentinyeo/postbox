function Save-WorkspaceNameCheck($Session, [string]$Id, [string[]]$Labels, [string[]]$Screenshots, [string]$Prefix = '') {
    $names = @('Alpha Workspace', 'Beta Workspace')
    foreach ($name in $names) {
        Assert-That ($Labels -ccontains "${Prefix}Slack $name") "$Id missing workspace name: $name"
    }
    foreach ($team in @('T0ABC123', 'T0DEF456')) {
        Assert-That ($Labels -cnotcontains "${Prefix}Slack $team") "$Id contains team-id label: $team"
    }
    $path = Join-Path $Session.evidence 'workspace-names.json'
    $checks = if (Test-Path $path) { Get-Content $path -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
    $checks[$Id] = @{ status = 'passed'; names = $names; labels = $Labels; screenshots = $Screenshots }
    $checks | ConvertTo-Json -Depth 12 | Set-Content $path
    Hub-Pass $Session $Id
}

function Read-InboxWorkspaceTooltips($Session, $Rows) {
    Add-Type -Path "$PSScriptRoot/menus.cs"
    Add-Type -Path "$PSScriptRoot/inbox-tooltip.cs"
    $list = Get-Edit (Get-Window $Session) '1016'
    $handle = [IntPtr]$list.Current.NativeWindowHandle
    $origin = [VerifyWindow+Point]::new()
    $client = [VerifyWindow+Rect]::new()
    Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'Cannot read chat list origin'
    Assert-That ([VerifyWindow]::GetClientRect($handle, [ref]$client)) 'Cannot read chat list bounds'
    $height = [UIntPtr]::Zero
    $top = [UIntPtr]::Zero
    Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x01A1, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$height) -ne [IntPtr]::Zero) 'Cannot read chat row height'
    Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x018E, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$top) -ne [IntPtr]::Zero) 'Cannot read chat list scroll position'
    Assert-That ($height.ToUInt64() -gt 10 -and $client.Right -gt 24) 'Chat list is too small for two hover points'
    $labels = @()
    foreach ($team in @('T0ABC123', 'T0DEF456')) {
        $index = 0
        while ($index -lt $Rows.Count -and $Rows[$index].view_account -ne $team) { $index++ }
        Assert-That ($index -lt $Rows.Count) 'Slack workspace missing from inbox'
        $offset = ($index - [int]$top.ToUInt64()) * [int]$height.ToUInt64() + [int]($height.ToUInt64() / 2)
        Assert-That ($offset -gt 0 -and $offset -lt $client.Bottom) 'Workspace row not visible for hover'
        $null = Get-App $Session
        $hoverForeground = [VerifyInboxTooltip]::DescribeWindow([VerifyWindow]::GetForegroundWindow())
        Add-Content (Join-Path $Session.evidence 'actions.log') "hover-foreground: $team $hoverForeground"
        [VerifyMenus]::Hover($Session.pid, $origin.X + 20, $origin.Y + $offset - 5)
        [VerifyMenus]::Hover($Session.pid, $origin.X + 24, $origin.Y + $offset)
        Add-Content (Join-Path $Session.evidence 'actions.log') "hover: $team"
        $expectedName = if ($team -eq 'T0ABC123') { 'Slack Alpha Workspace' } else { 'Slack Beta Workspace' }
        try {
            $tooltip = Wait-Until {
                $condition = [Windows.Automation.AndCondition]::new(
                    [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty, [int]$Session.pid),
                    [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'tooltips_class32')
                )
                $tips = [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
                foreach ($tip in $tips) {
                    if (-not $tip.Current.IsOffscreen -and $tip.Current.Name -ceq $expectedName) { return $tip.Current.Name }
                }
                $nativeTip = [VerifyMenus]::Find($Session.pid, 'tooltips_class32')
                if ($nativeTip -ne [IntPtr]::Zero) {
                    $bounds = [VerifyMenus]::Bounds($nativeTip)
                    $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
                    if ($bounds.Right -gt $screen.Left -and $bounds.Left -lt $screen.Right -and $bounds.Bottom -gt $screen.Top -and $bounds.Top -lt $screen.Bottom) {
                        $text = Read-EditText $nativeTip
                        if ($text -ceq $expectedName) { return $text }
                    }
                }
            } "combined inbox tooltip $expectedName"
        } catch {
            $tooltipFailure = $_
            $failure = Join-Path $Session.evidence 'inbox-tooltip-failure.txt'
            "team=$team expected=$expectedName row_index=$index error=$tooltipFailure`nhover_foreground=$hoverForeground" | Set-Content $failure
            try {
                [VerifyInboxTooltip]::Capture($handle, $origin.X + 24, $origin.Y + $offset) | Add-Content $failure
            } catch {
                Add-Content $failure "Native diagnostics failed: $_"
            }
            try {
                Save-Screen $Session 'inbox-tooltip-failure'
            } catch {
                Add-Content $failure "Failure screenshot failed: $_"
            }
            throw $tooltipFailure
        }
        Add-Content (Join-Path $Session.evidence 'actions.log') "tooltip: $team = $tooltip"
        $labels += $tooltip
        Save-Screen $Session "inbox-tooltip-$team"
    }
    Save-WorkspaceNameCheck $Session 'inbox-tooltip' $labels @('inbox-tooltip-T0ABC123.png', 'inbox-tooltip-T0DEF456.png')
}

function Save-ViewTitle($Session, [string]$Capture) {
    $state = Read-Control $Session status
    $label = if ($state.current_view.inbox) { 'Combined inbox' } else { $state.current_view.label }
    $expected = "$label - Wazig v$($state.version)"
    $actual = (Get-Window $Session).Current.Name
    $path = Join-Path $Session.evidence 'title.json'
    $titles = if (Test-Path $path) { Get-Content $path -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
    $titles[$Capture] = @{ actual = $actual; expected = $expected; version = $state.version; current_view = $state.current_view }
    $titles | ConvertTo-Json -Depth 12 | Set-Content $path
    Assert-That ($actual -ceq $expected) "Wrong inbox title: $actual; expected $expected"
    Save-Screen $Session $Capture
}

function Assert-AccountView($Session, [int]$Number, [string]$Account, [string]$Capture) {
    Send-Keys $Session "^$($Number + 1)"
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.current_view.account -eq $Account -and -not $state.current_view.inbox -and $state.chat_count -eq 2
    } "account view $Account"
    $state = Read-Control $Session status
    $rows = Read-Control $Session chats
    Assert-That ($rows.total -eq 2 -and @($rows.chats | Where-Object view_account -ne $Account).Count -eq 0) 'Account view leaked another account'
    Assert-That ($state.current_view.label -eq $state.view_order[$Number - 1].label) 'View label does not match saved position'
    $rows | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Capture.chats.json")
    Save-ViewTitle $Session $Capture
    return $rows.chats
}

function Assert-ViewShortcuts($Session, $Order) {
    $proof = @()
    for ($index = 0; $index -lt $Order.Count; $index++) {
        $key = "^$($index + 2)"
        Send-Keys $Session $key
        $wanted = $Order[$index]
        $null = Wait-Until {
            $state = Read-Control $Session status
            -not $state.current_view.inbox -and $state.current_view.provider -eq $wanted.provider -and $state.current_view.account -eq $wanted.account
        } "Ctrl+$($index + 2) opens saved account $($wanted.account)"
        $proof += @{ key = $key; current_view = (Read-Control $Session status).current_view }
        Save-Screen $Session "shortcut-account-$($index + 2)"
        Send-Keys $Session '^1'
        $null = Wait-Until { (Read-Control $Session status).current_view.inbox } 'Ctrl+1 opens combined inbox'
        $proof += @{ key = '^1'; current_view = (Read-Control $Session status).current_view }
    }
    Send-Keys $Session '^2'
    $null = Wait-Until { (Read-Control $Session status).current_view.account -eq $Order[0].account } 'first account before retired shortcuts'
    foreach ($number in 0..9) {
        $key = "%$number"
        Send-Keys $Session $key
        $state = Read-Control $Session status
        Assert-That (-not $state.current_view.inbox -and $state.current_view.account -eq $Order[0].account) "Retired Alt+$number changed the view"
        $proof += @{ key = $key; current_view = $state.current_view }
    }
    Send-Keys $Session '%i'
    $null = Wait-Until { (Read-Control $Session status).current_view.inbox } 'Alt+I remains an inbox alias'
    $proof += @{ key = '%i'; current_view = (Read-Control $Session status).current_view }
    $proof | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'view-shortcuts.json')
    Save-Screen $Session shortcut-inbox
    Send-Keys $Session '{F1}'
    Save-Screen $Session shortcut-help
    Send-Keys $Session '{ESC}'
}

function Invoke-ViewsJourney($Session, [string]$Messages, $Start) {
    $expected = @('personal', 'business', 'T0ABC123', 'T0DEF456')
    $null = Wait-Until { (Read-Control $Session status).view_order.Count -eq 6 } 'four populated account views, Telegram and Signal'
    $baseline = Read-Control $Session status
    Assert-That ($baseline.current_view.inbox -and $baseline.chat_count -eq 8) 'Combined inbox baseline missing'
    Assert-ViewShortcuts $Session $baseline.view_order
    $catalog = Read-Control $Session chats
    $catalog | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'views-catalog.json')
    for ($index = 0; $index -lt $expected.Count; $index++) {
        Assert-That ($baseline.view_order[$index].account -eq $expected[$index]) 'Default account order differs'
        $rows = @(Assert-AccountView $Session ($index + 1) $expected[$index] "view-$($index + 1)")
        if ($index -eq 0) { Save-ViewTitle $Session 'title-view-1' }
        Send-Keys $Session '^+{HOME}'
        $null = Wait-Until { (Read-Control $Session status).selected.id -eq $rows[0].id } 'first chat in account'
        Send-Keys $Session '^{TAB}'
        $null = Wait-Until { (Read-Control $Session status).selected.id -eq $rows[1].id } 'next chat within account'
        Send-Keys $Session '^+{TAB}'
        $null = Wait-Until { (Read-Control $Session status).selected.id -eq $rows[0].id } 'previous chat within account'
        Send-Keys $Session '^f'
        Send-Keys $Session 'Shared'
        $null = Wait-Until { $state = Read-Control $Session status; $state.chat_count -eq 1 -and $state.selected.view_account -eq $expected[$index] -and $state.selected.name -eq 'Verification Shared' } 'account-scoped search'
        Save-Screen $Session "search-$($index + 1)"
        Send-Keys $Session '{ESC}'
        $null = Wait-Until { (Read-Control $Session status).chat_count -eq 2 } 'account search cleared'
    }
    $labels = @((Read-Control $Session status).view_order | Where-Object provider -eq 'slack' | ForEach-Object label)
    Save-WorkspaceNameCheck $Session 'view-label' $labels @('view-3.png', 'view-4.png')
    Send-Keys $Session '^k'
    $palette = Get-PaletteWindow $Session
    Send-Keys $Session 'Show'
    $list = Get-Edit $palette '1072'
    $null = Wait-Until {
        $labels = @(Read-ListLabels $list)
        $labels -ccontains 'Show Slack Alpha Workspace' -and $labels -ccontains 'Show Slack Beta Workspace'
    } 'Show workspace commands'
    $labels = @(Read-ListLabels $list)
    Save-Screen $Session workspace-palette
    Save-WorkspaceNameCheck $Session 'palette' $labels @('workspace-palette.png') 'Show '
    Send-Keys $Session '{ESC}'
    $null = Assert-AccountView $Session 1 'personal' 'send-account'
    Send-Keys $Session '^+{HOME}^{TAB}'
    $target = (Read-Control $Session status).selected
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session 'Verification account send'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $sends = @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.accepted })
        $state.pending_sends -eq 0 -and $sends.Count -eq 1
    } 'one account-scoped send accepted'
    $sends = @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' })
    Assert-That (@($sends | Where-Object { $_.source_account -ne 'personal' -or $_.body.chat -ne $target.id }).Count -eq 0) 'Send reached another account'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object text -eq 'Verification account send').Count -eq 1 } 'sent message visible in source account'
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'sent.messages.json')
    Save-Screen $Session sent
    $null = Assert-AccountView $Session 2 'business' 'other-account'
    Send-Keys $Session '^+{HOME}^{TAB}'
    $null = Wait-Until {
        $shown = Read-Control $Session messages
        $shown.chat.view_account -eq 'business' -and $shown.messages.Count -gt 0 -and @($shown.messages | Where-Object text -eq 'Verification account send').Count -eq 0
    } 'shared contact in other account has no sent message'
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'other.messages.json')
    Save-Screen $Session isolated
    Send-Keys $Session '%i'
    $null = Wait-Until { $state = Read-Control $Session status; $state.current_view.inbox -and $state.chat_count -eq 8 } 'combined inbox'
    $inbox = Read-Control $Session chats
    for ($index = 1; $index -lt $inbox.chats.Count; $index++) {
        Assert-That ($inbox.chats[$index - 1].last_message_time -ge $inbox.chats[$index].last_message_time) 'Combined inbox is not newest first'
    }
    $inbox | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'inbox.chats.json')
    Save-Screen $Session inbox
    Save-ViewTitle $Session 'title-inbox'
    Read-InboxWorkspaceTooltips $Session $inbox.chats
    $null = Assert-AccountView $Session 1 'personal' 'before-drain'
    foreach ($remaining in @(1, 0)) {
        Send-Keys $Session '^+{HOME}'
        Assert-That ((Read-Control $Session messages).chat.view_account -eq 'personal') 'Archive target history belongs to the first account'
        Send-Keys $Session '^e'
        $null = Wait-Until {
            $state = Read-Control $Session status
            $state.pending_archives -eq 0 -and $state.chat_count -eq $remaining
        } 'account archive held in Wazig'
    }
    Invoke-PaletteCommand $Session 'Refresh'
    Send-Keys $Session '^2'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.current_view.account -eq 'personal' -and -not $state.current_view.inbox -and $state.chat_count -eq 0 -and $state.pending_archives -eq 0
    } 'drained account retains Ctrl+2 with an empty list'
    $drained = Read-Control $Session status
    Assert-That (($drained.view_order | ConvertTo-Json -Depth 12 -Compress) -ceq ($baseline.view_order | ConvertTo-Json -Depth 12 -Compress)) 'Draining changed account positions'
    Assert-That ((Read-Control $Session chats).total -eq 0) 'Drained account still has visible chats'
    Save-ViewTitle $Session 'drained-alt1'
    $null = Assert-AccountView $Session 2 'business' 'drained-alt2'
    Send-Keys $Session '^2'
    Invoke-PaletteCommand $Session 'Show archived chats'
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 2 } 'drained account archived chats'
    foreach ($remaining in @(1, 0)) {
        Send-Keys $Session '^+{HOME}'
        Assert-That ((Read-Control $Session messages).chat.view_account -eq 'personal') 'Archive target history belongs to the first account'
        Send-Keys $Session '^e'
        $null = Wait-Until { $state = Read-Control $Session status; $state.pending_archives -eq 0 -and $state.chat_count -eq $remaining } 'restore archived fixture chat'
    }
    Invoke-PaletteCommand $Session 'Show inbox chats'
    $null = Assert-AccountView $Session 1 'personal' 'restored-account'
    Invoke-PaletteCommand $Session 'Sort views' sort-command
    Save-Screen $Session sort-before
    $list = Get-Edit (Get-PaletteWindow $Session) '1072'
    $null = Wait-Until { (Read-ListCount $list) -eq 6 } 'four populated account rows, Telegram and Signal in Sort views'
    Save-WorkspaceNameCheck $Session 'sort-views' @(Read-ListLabels $list) @('sort-before.png')
    Send-Keys $Session '^{DOWN}'
    $null = Wait-Until { (Read-Control $Session status).view_order[0].account -eq 'business' } 'view move saved immediately'
    $preferences = "HKCU:\Software\MessagesVerification\$($Session.id)\Software\Messages"
    $savedOrder = (Get-ItemProperty $preferences).ViewOrder
    Assert-That ($savedOrder.StartsWith("whatsapp:business`nwhatsapp:personal`n")) 'ViewOrder not saved at move time'
    Set-Content (Join-Path $Session.evidence 'view-order.txt') $savedOrder -NoNewline
    Save-Screen $Session sort-moved
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { (Read-Control $Session status).current_view.account -eq 'personal' } 'Enter switches to moved selection'
    Save-Screen $Session sort-selected
    Invoke-PaletteCommand $Session 'Sort views'
    Send-Keys $Session '{ESC}'
    Save-Screen $Session sort-closed
    $old = Get-App $Session
    $oldPid = $Session.pid
    $oldTicks = $Session.startTicks
    Invoke-PaletteCommand $Session 'Quit Messages'
    $null = Wait-Until { $old.Refresh(); $old.HasExited } 'fixture app closed for restart'
    $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $app = [Diagnostics.Process]::Start($Start)
    $Session.pid = $app.Id
    $Session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    @{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $Session.pid; new_start = $Session.startTicks; root = $Session.root; id = $Session.id; sha256 = $Session.sha256 } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'restart.json')
    $null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'restarted fixture window'
    [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 2 } 'saved account view restored'
    Invoke-Doctor $Session | Out-Null
    $null = Assert-AccountView $Session 1 'business' 'restart-1'
    $null = Assert-AccountView $Session 2 'personal' 'restart-2'
    $null = Assert-AccountView $Session 3 'T0ABC123' 'restart-3'
    $null = Assert-AccountView $Session 4 'T0DEF456' 'restart-4'
    Save-Screen $Session after
    return $app
}
