$script:PaletteRowLimit = 10
$script:PaletteDot = [string][char]0xB7
$script:PaletteArchivedChats = [ordered]@{
    whatsapp = @{ id = 'personal:15550000031@s.whatsapp.net'; name = 'Archived Person Alpha'; provider = 'whatsapp' }
    telegram = @{ id = 'telegram:user:7001001'; name = 'Archived Telegram Beta'; provider = 'telegram' }
    slack = @{ id = 'slack:T0PALETTE:C0000000002'; name = 'Archived Slack Gamma'; provider = 'slack' }
    signal = @{ id = 'signal:fixture-search'; name = 'Archived Signal Delta'; provider = 'signal' }
}
$script:PaletteInboxChats = @(
    @{ id = 'personal:15550000021@s.whatsapp.net'; slug = 'epsilon'; name = 'Inbox WhatsApp Epsilon'; provider = 'whatsapp' },
    @{ id = 'personal:15550000022@s.whatsapp.net'; slug = 'zeta'; name = 'Inbox WhatsApp Zeta'; provider = 'whatsapp' },
    @{ id = 'slack:T0PALETTE:C0000000001'; slug = 'delta'; name = 'Inbox Slack Delta'; provider = 'slack' }
)

function Get-ArchivedPaletteLabel([string]$Name) {
    return "$Name  $script:PaletteDot  Archived"
}

function Add-PaletteFailure([string]$Step, [string]$Cause, [string]$Detail) {
    $script:PaletteFailures.Add([ordered]@{ step = $Step; cause = $Cause; detail = $Detail })
    Add-Content (Join-Path $script:PaletteSession.evidence 'actions.log') "palette-archived FAIL $Step [$Cause] $Detail"
}

function Close-PaletteWindow($Session) {
    Send-Keys $Session '{ESC}'
    $owner = Get-Window $Session
    $null = Wait-Until {
        $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'MessagesPalette')
        $open = $false
        foreach ($window in $owner.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)) {
            if ($window.Current.ProcessId -eq $Session.pid) { $open = $true }
        }
        -not $open
    } 'palette closed'
}

function Read-PaletteLabelsOnce($List) {
    try {
        return @{ labels = [string[]]@(Read-ListLabels $List | ForEach-Object { [string]$_ }) }
    } catch {
        return $null
    }
}

function Invoke-PaletteQuery($Session, [string]$Query, [string]$Expected, [int]$Seconds, [string]$Capture = '') {
    Send-Keys $Session '^k'
    $palette = Get-PaletteWindow $Session
    $edit = Get-Edit $palette '1064'
    $list = Get-Edit $palette '1072'
    Send-Keys $Session $Query
    $null = Wait-Until { (Read-Edit $edit) -ceq $Query } "palette query $Query"
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    $labels = [string[]]@()
    do {
        $read = Read-PaletteLabelsOnce $list
        if ($null -ne $read) {
            $labels = [string[]]@($read.labels)
            if ($labels -ccontains $Expected) { break }
        }
        [System.Threading.Thread]::Sleep(250)
    } while ([DateTime]::UtcNow -lt $deadline)
    $result = [ordered]@{
        query = $Query
        expected = $Expected
        labels = $labels
        rows = $labels.Count
        index = [Array]::IndexOf($labels, $Expected)
        matches = @($labels | Where-Object { $_ -ceq $Expected }).Count
    }
    if ($Capture) {
        Save-Screen $Session $Capture
        $result | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session.evidence "$Capture.palette.json")
    }
    Close-PaletteWindow $Session
    return $result
}

function Test-PaletteTarget($Session, [string]$Step, [string]$ViewLabel, [string]$Name, [string]$Expected, [int]$Seconds, [string]$Cause, [string]$Capture = '') {
    $result = Invoke-PaletteQuery $Session $Name $Expected $Seconds $Capture
    $entry = [ordered]@{ step = $Step; view = $ViewLabel; query = $Name; expected = $Expected; found = ($result.index -ge 0); index = $result.index; matches = $result.matches; rows = $result.rows; labels = $result.labels; screenshot = $Capture }
    $script:PaletteMatrix.Add($entry)
    $shown = ($result.labels | Select-Object -First 12) -join ' | '
    if ($result.index -lt 0) {
        Add-PaletteFailure $Step $Cause "view '$ViewLabel': no palette row '$Expected' for query '$Name'; $($result.rows) rows: $shown"
        return $false
    }
    if ($result.matches -ne 1) {
        Add-PaletteFailure $Step 'duplicate-row' "view '$ViewLabel': $($result.matches) rows equal '$Expected'"
        return $false
    }
    if ($result.index -ge $script:PaletteRowLimit) {
        Add-PaletteFailure $Step '3 below-the-fold' "view '$ViewLabel': row '$Expected' is at index $($result.index), beyond the first $script:PaletteRowLimit rows"
        return $false
    }
    Hub-Pass $Session $Step | Out-Null
    return $true
}

function Switch-PaletteView($Session, [int]$Position) {
    $order = @((Read-Control $Session status).view_order)
    Send-Keys $Session "^$($Position + 1)"
    $label = [string]$order[$Position - 1].label
    $null = Wait-Until {
        $state = Read-Control $Session status
        -not $state.current_view.inbox -and [string]$state.current_view.label -ceq $label
    } "view $Position $label"
    return $label
}

function Switch-PaletteAll($Session) {
    Send-Keys $Session '%i'
    $null = Wait-Until { (Read-Control $Session status).current_view.inbox } 'combined inbox view'
}

function Get-ArchivedCause([string]$Provider, [string]$ViewProvider) {
    if ($Provider -eq 'whatsapp') {
        if ($ViewProvider -in @('all', 'whatsapp')) { return 'unexpected: archived WhatsApp row missing in a view that already searched it' }
        return '1 view gate: archived search runs only when the active view includes WhatsApp'
    }
    if ($ViewProvider -in @('all', 'whatsapp')) { return '2 people index drops hub ids without @' }
    return '1+2 view gate and people index drop hub ids without @'
}

function Wait-PaletteArchivedScan($Session) {
    try {
        $null = Wait-Until {
            @(Read-BridgeRequests $Session | Where-Object { $_.method -eq 'GET' -and $_.status -eq 200 -and $_.wire_path -like '/v1/wazig/chats*archived=true*' }).Count -ge 1
        } 'archived scan request reached the hub' 90
        Hub-Pass $Session 'archived-scan-request' | Out-Null
    } catch {
        Add-PaletteFailure 'scan' 'scan never requested' "the app never sent GET /v1/wazig/chats?archived=true within 90 s: $_"
    }
}

function Test-PaletteEnter($Session, [string]$Step, [string]$ViewLabel, [string]$ViewProvider, $Chat, [bool]$CheckHistory) {
    $name = $Chat.name
    $expected = Get-ArchivedPaletteLabel $name
    $before = @(Read-BridgeRequests $Session).Count
    Send-Keys $Session '^k'
    $palette = Get-PaletteWindow $Session
    $edit = Get-Edit $palette '1064'
    $list = Get-Edit $palette '1072'
    Send-Keys $Session $name
    $null = Wait-Until { (Read-Edit $edit) -ceq $name } "palette query $name"
    $deadline = [DateTime]::UtcNow.AddSeconds(6)
    $labels = [string[]]@()
    do {
        $read = Read-PaletteLabelsOnce $list
        if ($null -ne $read) {
            $labels = [string[]]@($read.labels)
            if ($labels -ccontains $expected) { break }
        }
        [System.Threading.Thread]::Sleep(250)
    } while ([DateTime]::UtcNow -lt $deadline)
    Save-Screen $Session "$Step-palette"
    if (-not ($labels -ccontains $expected)) {
        Add-PaletteFailure $Step (Get-ArchivedCause $Chat.provider $ViewProvider) "view '$ViewLabel': no archived row '$expected' to press Enter on; rows: $(($labels | Select-Object -First 12) -join ' | ')"
        Close-PaletteWindow $Session
        return
    }
    Send-Keys $Session '{ENTER}'
    try {
        $null = Wait-Until { [string](Read-Control $Session status).selected.id -ceq $Chat.id } "selected $($Chat.id)"
    } catch {
        $selectedId = [string](Read-Control $Session status).selected.id
        Add-PaletteFailure $Step '4 identity mismatch' "view '$ViewLabel': Enter on '$expected' left selected.id '$selectedId' instead of '$($Chat.id)'; status says: $(Read-Control $Session status | ConvertTo-Json -Depth 4 -Compress)"
        try { Close-PaletteWindow $Session } catch { }
        return
    }
    Save-Screen $Session $Step
    $state = Read-Control $Session status
    $after = @(Read-BridgeRequests $Session | Select-Object -Skip $before)
    $archiveWrites = @($after | Where-Object { $_.method -eq 'POST' -and $_.wire_path -eq '/v1/wazig/archive' -and $_.body.chat -ceq $Chat.id })
    if ($archiveWrites.Count -gt 0) {
        Add-PaletteFailure $Step 'unarchived by Enter' "view '$ViewLabel': Enter on '$expected' sent $($archiveWrites.Count) POST /v1/wazig/archive for $($Chat.id), body $($archiveWrites[0].body | ConvertTo-Json -Compress)"
        return
    }
    if ($CheckHistory) {
        try {
            $null = Wait-Until { @(Read-BridgeRequests $Session | Select-Object -Skip $before | Where-Object { $_.method -eq 'GET' -and ([uri]::UnescapeDataString([string]$_.wire_path)) -like "/v1/wazig/messages*chat=$($Chat.id)*" }).Count -ge 1 } "history request for $($Chat.id)" 10
        } catch {
            Add-PaletteFailure $Step 'no history request' "view '$ViewLabel': selected $($Chat.id) but the hub never received GET /v1/wazig/messages for it"
            return
        }
    }
    if (-not [bool]$state.selected.archived) {
        Add-PaletteFailure $Step 'not marked archived' "view '$ViewLabel': selected $($Chat.id) reports archived=$($state.selected.archived)"
        return
    }
    Hub-Pass $Session $Step | Out-Null
}

function Invoke-PaletteArchivedJourney($Session) {
    $script:PaletteSession = $Session
    $script:PaletteFailures = [Collections.Generic.List[object]]::new()
    $script:PaletteMatrix = [Collections.Generic.List[object]]::new()
    $status = Read-Control $Session status
    $views = @($status.view_order)
    $views | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session.evidence 'view-order.json')
    Assert-That ($views.Count -ge 2 -and @($views | Where-Object provider -eq 'slack').Count -ge 1 -and @($views | Where-Object provider -eq 'whatsapp').Count -ge 1) 'Fixture did not produce WhatsApp and Slack account views'
    $archived = $script:PaletteArchivedChats
    try {
        Wait-PaletteArchivedScan $Session

        Switch-PaletteAll $Session
        $control = $script:PaletteInboxChats[2]
        $null = Test-PaletteTarget $Session 'a0-inbox-control' 'combined inbox' $control.name $control.name 6 'positive control: palette cannot find a visible inbox chat' 'a0-inbox-control'
        $first = $true
        foreach ($key in $archived.Keys) {
            $chat = $archived[$key]
            $seconds = if ($first) { 30 } else { 6 }
            $first = $false
            $null = Test-PaletteTarget $Session "a-all-$key" 'combined inbox' $chat.name (Get-ArchivedPaletteLabel $chat.name) $seconds (Get-ArchivedCause $chat.provider 'all') "a-all-$key"
        }
        $crowded = Invoke-PaletteQuery $Session 'Archived' (Get-ArchivedPaletteLabel $archived.whatsapp.name) 3 'a-all-crowded'
        $script:PaletteMatrix.Add([ordered]@{ step = 'a-all-crowded'; view = 'combined inbox'; query = 'Archived'; informational = $true; rows = $crowded.rows; labels = $crowded.labels; indexes = @($archived.Keys | ForEach-Object { [Array]::IndexOf($crowded.labels, (Get-ArchivedPaletteLabel $archived[$_].name)) }) })

        for ($position = 1; $position -le [Math]::Min($views.Count, 8); $position++) {
            $viewLabel = Switch-PaletteView $Session $position
            $viewProvider = [string]$views[$position - 1].provider
            Save-Screen $Session "b-view-$position"
            foreach ($key in $archived.Keys) {
                $chat = $archived[$key]
                $null = Test-PaletteTarget $Session "b-$position-$key" $viewLabel $chat.name (Get-ArchivedPaletteLabel $chat.name) 6 (Get-ArchivedCause $chat.provider $viewProvider) "b-$position-$key"
            }
            foreach ($inbox in $script:PaletteInboxChats) {
                $cause = '1 palette lists only chats of the active view'
                $null = Test-PaletteTarget $Session "b-$position-inbox-$($inbox.slug)" $viewLabel $inbox.name $inbox.name 6 $cause
            }
        }

        Switch-PaletteAll $Session
        foreach ($key in $archived.Keys) {
            Test-PaletteEnter $Session "c-all-$key" 'combined inbox' 'all' $archived[$key] $true
        }
        Send-Keys $Session '^k'
        $palette = Get-PaletteWindow $Session
        $edit = Get-Edit $palette '1064'
        $list = Get-Edit $palette '1072'
        Send-Keys $Session 'Archived'
        $null = Wait-Until { (Read-Edit $edit) -ceq 'Archived' } 'shared name search'
        $labels = [string[]]@(Read-ListLabels $list)
        $frequent = Get-ArchivedPaletteLabel $archived.telegram.name
        $rare = Get-ArchivedPaletteLabel $archived.whatsapp.name
        Save-Screen $Session 'frequency-results'
        $handle = [IntPtr]$list.Current.NativeWindowHandle
        $origin = [VerifyWindow+Point]::new()
        Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'Cannot locate search results'
        $rowHeight = [UIntPtr]::Zero
        Assert-That ([VerifyWindow]::ReadListMetric($handle, 0x01A1, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$rowHeight) -ne [IntPtr]::Zero) 'Cannot read search row height'
        $desktop = [System.Windows.Forms.SystemInformation]::VirtualScreen
        [ordered]@{ labels = $labels; frequent = $frequent; rare = $rare; list_x = $origin.X - $desktop.Left; list_y = $origin.Y - $desktop.Top; row_height = $rowHeight.ToUInt64() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session.evidence 'frequency-results.json')
        if ([Array]::IndexOf($labels, $frequent) -lt 0 -or [Array]::IndexOf($labels, $frequent) -ge [Array]::IndexOf($labels, $rare)) {
            Add-PaletteFailure 'frequency' 'sent-message ordering' "Frequent contact not ahead of rare contact: $($labels -join ' | ')"
        }
        $image = [Drawing.Bitmap]::new((Join-Path $Session.evidence 'frequency-results.png'))
        $badges = [ordered]@{}
        try {
            foreach ($key in $archived.Keys) {
                $row = [Array]::IndexOf($labels, (Get-ArchivedPaletteLabel $archived[$key].name))
                Assert-That ($row -ge 0) "Missing $key result"
                $left = $origin.X - $desktop.Left
                $top = $origin.Y - $desktop.Top + $row * [int]$rowHeight.ToUInt64()
                $colour = switch ($key) { 'whatsapp' { @(37, 211, 102) } 'telegram' { @(42, 171, 238) } 'signal' { @(58, 118, 240) } 'slack' { @(51, 51, 51) } }
                $pixels = 0
                for ($y = 11; $y -lt 29; $y++) {
                    for ($x = 16; $x -lt 36; $x++) {
                        $pixel = $image.GetPixel($left + $x, $top + $y)
                        if ([Math]::Abs([int]$pixel.R - $colour[0]) -le 4 -and [Math]::Abs([int]$pixel.G - $colour[1]) -le 4 -and [Math]::Abs([int]$pixel.B - $colour[2]) -le 4) { $pixels++ }
                    }
                }
                $badges[$key] = $pixels
                if ($pixels -lt 20) { Add-PaletteFailure 'network-badge' 'missing inline icon' "$key row has only $pixels badge pixels" }
            }
        } finally { $image.Dispose() }
        $badges | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'frequency-badges.json')
        Close-PaletteWindow $Session

        foreach ($key in $archived.Keys) {
            $chat = $archived[$key]
            $position = 0
            for ($index = 0; $index -lt $views.Count; $index++) {
                if ($views[$index].provider -eq $chat.provider -and $position -eq 0) { $position = $index + 1 }
            }
            if ($position -eq 0 -or $position -gt 8) {
                Add-PaletteFailure "c-own-$key" 'no own view' "no account view for provider $($chat.provider) in the first eight positions"
                continue
            }
            $viewLabel = Switch-PaletteView $Session $position
            Test-PaletteEnter $Session "c-own-$key" $viewLabel $chat.provider $chat $false
        }

    } catch {
        Add-PaletteFailure 'journey-aborted' 'harness error' "$_"
    }
    try { Switch-PaletteAll $Session } catch { }
    $requests = Read-BridgeRequests $Session
    $requests | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'palette-archived.requests.json')
    $ids = @($archived.Keys | ForEach-Object { $archived[$_].id })
    $unarchived = @($requests | Where-Object { $_.method -eq 'POST' -and $_.wire_path -eq '/v1/wazig/archive' -and $ids -ccontains $_.body.chat })
    if ($unarchived.Count -gt 0) {
        Add-PaletteFailure 'no-archive-writes' 'unarchived by Enter' "$($unarchived.Count) POST /v1/wazig/archive requests touched archived chats"
    }
    [ordered]@{
        row_limit = $script:PaletteRowLimit
        views = $views
        matrix = $script:PaletteMatrix
        failures = $script:PaletteFailures
    } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $Session.evidence 'palette-archived.json')
    if ($script:PaletteFailures.Count -gt 0) {
        $lines = @($script:PaletteFailures | ForEach-Object { "FAILED $($_.step) [cause $($_.cause)]: $($_.detail)" })
        throw "Ctrl+K misses archived or other-view chats in $($script:PaletteFailures.Count) step(s)`n$($lines -join "`n")"
    }
    Hub-Pass $Session 'palette-archived-all' | Out-Null
}
