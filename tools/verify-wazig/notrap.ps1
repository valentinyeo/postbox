. "$PSScriptRoot/menus.ps1"

function Select-NotrapView($Session, $Order, [int]$Number) {
    Send-Keys $Session "%$($Number + 1)"
    $wanted = $Order[$Number - 1]
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.current_view.provider -eq $wanted.provider -and $state.current_view.account -eq $wanted.account -and $state.current_view.label -eq $wanted.label -and -not $state.current_view.inbox
    } "Alt+$($Number + 1) reaches saved view"
    return (Read-Control $Session status)
}

function Focus-Canvas($Session, $Point) {
    [VerifyMenus]::Click($Session.pid, $Point.X, $Point.Y, $false)
    $null = Wait-Until {
        $focused = [Windows.Automation.AutomationElement]::FocusedElement
        $focused.Current.ProcessId -eq $Session.pid -and $focused.Current.AutomationId -ceq '1024'
    } 'canvas holds keyboard focus'
}

function Invoke-NotrapJourney($Session) {
    $startup = Read-Control $Session status
    Assert-That ($startup.view -notin @('signal', 'telegram') -and $startup.chat_count -gt 0) 'Saved unlinked view trapped startup'
    Assert-That $startup.current_view.inbox 'Empty saved provider did not fall back to the combined inbox'
    $order = @($startup.view_order)
    Assert-That ($order.Count -eq 6) 'Missing account views in no-trap fixture'
    Assert-That (@($order | Where-Object provider -eq 'signal').Count -eq 1 -and @($order | Where-Object provider -eq 'telegram').Count -eq 1) 'Missing empty provider views'
    $rows = (Read-Control $Session chats).chats
    Assert-That ($rows.Count -eq 8 -and @($rows | Where-Object { $_.provider -in @('signal', 'telegram') }).Count -eq 0) 'Unlinked providers returned chats'
    Save-Screen $Session startup
    Hub-Pass $Session startup-fallback
    $transitions = @()
    for ($source = 1; $source -le $order.Count; $source++) {
        $state = Select-NotrapView $Session $order $source
        $empty = $order[$source - 1].provider -in @('signal', 'telegram')
        Assert-That ($state.chat_count -eq $(if ($empty) { 0 } else { 2 })) 'Wrong provider chat count'
        Save-Screen $Session "view-$source"
        Send-Keys $Session '^f'
        Send-Keys $Session 'no-trap-search'
        $null = Wait-Until { $state = Read-Control $Session status; $state.search -eq 'no-trap-search' -and $state.chat_count -eq 0 } 'search accepts input in every view'
        Send-Keys $Session '{ESC}'
        $null = Wait-Until {
            $state = Read-Control $Session status
            $state.search -eq '' -and $state.chat_count -eq $(if ($empty) { 0 } else { 2 }) -and $state.current_view.account -eq $order[$source - 1].account
        } 'Esc clears search in every view'
        Send-Keys $Session '{ESC}'
        $null = Wait-Until {
            $state = Read-Control $Session status
            $state.chat_count -gt 0 -and ($state.current_view.inbox -or -not $empty)
        } 'Esc leaves an empty provider view and status still responds'
        $state = Read-Control $Session status
        $state | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "esc-$source.state.json")
        $null = Select-NotrapView $Session $order 1
        Read-Control $Session status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "escape-to-first-$source.state.json")
        for ($target = 1; $target -le $order.Count; $target++) {
            $null = Select-NotrapView $Session $order $source
            $state = Select-NotrapView $Session $order $target
            $transitions += @{ source = $source; target = $target; current_view = $state.current_view }
            if ($source -eq 1 -and $target -le 2) { Save-Screen $Session "shortcut-alt-$($target + 1)" }
        }
        foreach ($key in @('%1', '%i', 'gi')) {
            $null = Select-NotrapView $Session $order $source
            if ($key -eq 'gi') { (Get-Edit (Get-Window $Session) '1016').SetFocus() }
            Send-Keys $Session $key
            $null = Wait-Until { $state = Read-Control $Session status; $state.current_view.inbox -and $state.chat_count -eq 8 } 'Alt inbox shortcut from every view'
            $transitions += @{ source = $source; target = $key; current_view = (Read-Control $Session status).current_view }
            if ($source -eq 1) {
                $stage = switch ($key) { '%1' { 'alt-1' } '%i' { 'alt-i' } 'gi' { 'g-i' } }
                Save-Screen $Session "shortcut-$stage"
            }
        }
    }
    $null = Select-NotrapView $Session $order 1
    Send-Keys $Session '^1'
    $state = Read-Control $Session status
    Assert-That ($state.current_view.account -eq $order[0].account -and -not $state.current_view.inbox) 'Ctrl+1 must not switch views'
    Save-Screen $Session 'ctrl-one'
    Send-Keys $Session '%1'
    $null = Wait-Until { (Read-Control $Session status).current_view.inbox } 'Combined inbox for the Ctrl number jump'
    $rows = (Read-Control $Session chats).chats
    Assert-That ($rows.Count -ge 3) 'Too few chats for the Ctrl number jump'
    Send-Keys $Session '^3'
    $null = Wait-Until { (Read-Control $Session status).selected.id -ceq $rows[2].id } 'Ctrl+3 opens the third top chat'
    $jumped = Read-Control $Session status
    Send-Keys $Session '^1'
    $null = Wait-Until { (Read-Control $Session status).selected.id -ceq $rows[0].id } 'Ctrl+1 opens the first top chat'
    Assert-That ($jumped.current_view.inbox) 'Ctrl+3 must not switch views'
    @{ first = $rows[0].id; third = $rows[2].id; selected = (Read-Control $Session status).selected.id; view = $jumped.current_view } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session.evidence 'ctrl-chat-jump.json')
    Save-Screen $Session 'ctrl-number-jump'
    $null = Select-NotrapView $Session $order 1
    Send-Keys $Session '^f'
    Send-Keys $Session 'gi'
    $null = Wait-Until { (Read-Control $Session status).search -eq 'gi' } 'search preserves typed gi'
    Save-Screen $Session 'typed-gi'
    Send-Keys $Session '{ESC}'
    (Get-Edit (Get-Window $Session) '1016').SetFocus()
    Send-Keys $Session 'g'
    Send-Keys $Session 'x'
    Send-Keys $Session 'i'
    $state = Read-Control $Session status
    Assert-That ($state.current_view.account -eq $order[0].account -and -not $state.current_view.inbox) 'intervening key cancels g prefix'
    Save-Screen $Session 'cancelled-gi'
    $canvas = Get-Edit (Get-Window $Session) '1024'
    $bubble = Wait-Until {
        (Read-Control $Session messages).messages | Where-Object { $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[3] -gt $_.bubble[1] } | Select-Object -First 1
    } 'synthetic message bubble painted'
    $point = [VerifyWindow+Point]::new()
    $point.X = [int](($bubble.bubble[0] + $bubble.bubble[2]) / 2)
    $point.Y = [int](($bubble.bubble[1] + $bubble.bubble[3]) / 2)
    $focusPoint = [VerifyWindow+Point]::new()
    $focusPoint.X = [int]($bubble.bubble[0] + ($bubble.bubble[2] - $bubble.bubble[0]) / 4)
    $focusPoint.Y = $point.Y
    Assert-That ([VerifyWindow]::ClientToScreen([IntPtr]$canvas.Current.NativeWindowHandle, [ref]$point)) 'Canvas screen origin unavailable'
    Assert-That ([VerifyWindow]::ClientToScreen([IntPtr]$canvas.Current.NativeWindowHandle, [ref]$focusPoint)) 'Canvas focus screen origin unavailable'
    $beforeMenu = Read-Control $Session status
    Focus-Canvas $Session $focusPoint
    Send-Keys $Session 'g'
    [VerifyMenus]::Click($Session.pid, $point.X, $point.Y, $true)
    Add-Content (Join-Path $Session.evidence 'actions.log') 'SendInput: right-click synthetic message for prefix cancellation'
    $menuHandle = Wait-Popup $Session '#32768'
    $menuElement = [Windows.Automation.AutomationElement]::FromHandle($menuHandle)
    Assert-That ($menuElement.Current.ProcessId -eq $Session.pid -and $menuElement.Current.ClassName -eq '#32768') 'Wrong native message menu'
    Save-Screen $Session 'prefix-menu-open'
    Close-Popup $Session '#32768'
    $afterMenu = Read-Control $Session status
    Assert-That ($afterMenu.menu_entry_count -eq $beforeMenu.menu_entry_count + 1 -and $null -ne $afterMenu.menu_prefix_age_ms -and $afterMenu.menu_prefix_age_ms -le 900 -and -not $afterMenu.menu_prefix_pending) 'Menu must clear a live G prefix'
    Focus-Canvas $Session $focusPoint
    Send-Keys $Session 'i'
    $afterI = Read-Control $Session status
    Assert-That ($afterI.current_view.account -eq $order[0].account -and -not $afterI.current_view.inbox) 'I after menu must not open inbox'
    @{ menu_class = '#32768'; menu_pid = $Session.pid; menu_handle = $menuHandle.ToInt64(); closed = ((Find-Popup $Session '#32768') -eq [IntPtr]::Zero); before_count = $beforeMenu.menu_entry_count; after_count = $afterMenu.menu_entry_count; prefix_age_ms = $afterMenu.menu_prefix_age_ms; prefix_pending = $afterMenu.menu_prefix_pending; current_view = $afterI.current_view } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'prefix-menu.json')
    Save-Screen $Session 'prefix-menu-closed'
    $compose = Get-Edit (Get-Window $Session) '1032'
    Assert-That ($compose.Current.IsEnabled -and (Read-Edit $compose) -ceq '') 'Fixture composer must start empty'
    (Get-Edit (Get-Window $Session) '1016').SetFocus()
    Send-Keys $Session 'g'
    $compose.SetFocus()
    Send-Keys $Session 'i'
    $null = Wait-Until { (Read-Edit $compose) -ceq 'i' } 'focus change cancels prefix and types i'
    $state = Read-Control $Session status
    Assert-That ($state.current_view.account -eq $order[0].account -and -not $state.current_view.inbox) 'focus change must not open inbox'
    $focused = [Windows.Automation.AutomationElement]::FocusedElement
    Assert-That ($focused.Current.ProcessId -eq $Session.pid -and $focused.Current.AutomationId -ceq '1032' -and $focused.Current.HasKeyboardFocus) 'Composer lost focus after prefix'
    @{ text = (Read-Edit $compose); focus_id = $focused.Current.AutomationId; focus_pid = $focused.Current.ProcessId; current_view = $state.current_view } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'focus-cancelled-gi.json')
    Save-Screen $Session 'focus-cancelled-gi'
    Send-Keys $Session '^a{BACKSPACE}'
    Send-Keys $Session 'gi'
    $null = Wait-Until { (Read-Edit $compose) -ceq 'gi' } 'composer preserves typed gi'
    $focused = [Windows.Automation.AutomationElement]::FocusedElement
    Assert-That ($focused.Current.ProcessId -eq $Session.pid -and $focused.Current.AutomationId -ceq '1032' -and $focused.Current.HasKeyboardFocus) 'Composer lost focus'
    $state = Read-Control $Session status
    Assert-That ($state.current_view.account -eq $order[0].account -and -not $state.current_view.inbox) 'typed gi changed view'
    @{ text = (Read-Edit $compose); focus_id = $focused.Current.AutomationId; focus_pid = $focused.Current.ProcessId; current_view = $state.current_view } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'composer-gi.json')
    Save-Screen $Session 'composer-gi'
    Send-Keys $Session '^a{BACKSPACE}'
    $null = Wait-Until { (Read-Edit $compose) -ceq '' } 'composer draft restored'
    @{ text = (Read-Edit $compose) } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'composer-restored.json')
    Send-Keys $Session '%1'
    $null = Wait-Until { (Read-Control $Session status).current_view.inbox } 'return to combined inbox'
    $bounds = (Get-Window $Session).Current.BoundingRectangle
    $captureX = [int]$bounds.X; $captureY = [int]$bounds.Y
    $captureWidth = [int]$bounds.Width; $captureHeight = [int]$bounds.Height
    Assert-That ($captureWidth -gt 0 -and $captureHeight -gt 0) 'Invalid fixture window bounds'
    $video = Join-Path $Session.evidence 'ticketProof.mp4'
    $ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    $captureJob = $null; $recorder = $null
    try {
        if ($ffmpeg) {
            $size = "{0}x{1}" -f $captureWidth, $captureHeight
            $arguments = @('-y', '-f', 'gdigrab', '-framerate', '5', '-offset_x', $captureX, '-offset_y', $captureY, '-video_size', $size, '-i', 'desktop', '-t', '20', '-an', '-c:v', 'mpeg4', '-q:v', '5', "`"$video`"")
            $recorder = Start-Process -FilePath $ffmpeg.Source -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $Session.evidence 'ticketProof-ffmpeg.log')
            $null = Wait-Until { (Test-Path $video) -and (Get-Item $video).Length -gt 0 } 'fixture recorder started'
            $recordStarted = [DateTime]::UtcNow.ToString('o')
        } else {
            $frameDir = Join-Path $Session.evidence 'ticketProof-frames'
            New-Item -ItemType Directory -Path $frameDir -ErrorAction Stop | Out-Null
            $captureJob = Start-ThreadJob -ArgumentList $frameDir, $captureX, $captureY, $captureWidth, $captureHeight -ScriptBlock {
                param($frameDir, $x, $y, $width, $height)
                $ErrorActionPreference = 'Stop'
                Add-Type -AssemblyName System.Drawing
                $clock = [Diagnostics.Stopwatch]::StartNew()
                $frames = @()
                for ($index = 0; $index -lt 100; $index++) {
                    $delay = $index * 200 - $clock.ElapsedMilliseconds
                    if ($delay -gt 0) { Start-Sleep -Milliseconds $delay }
                    $bitmap = [Drawing.Bitmap]::new($width, $height)
                    $graphics = [Drawing.Graphics]::FromImage($bitmap)
                    try {
                        $graphics.CopyFromScreen($x, $y, 0, 0, $bitmap.Size)
                        $frameTime = [DateTime]::UtcNow.ToString('o')
                        $elapsed = $clock.ElapsedMilliseconds
                        $name = 'frame-{0:D3}.png' -f $index
                        $bitmap.Save((Join-Path $frameDir $name), [Drawing.Imaging.ImageFormat]::Png)
                        $frames += @{ file = $name; utc = $frameTime; elapsed_ms = $elapsed }
                    } finally { $graphics.Dispose(); $bitmap.Dispose() }
                }
                @{ mode = 'frames'; width = $width; height = $height; fps = 5; frames = $frames } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path (Split-Path $frameDir) 'ticketProof-capture.json')
            }
            $null = Wait-Until { Test-Path (Join-Path $frameDir 'frame-000.png') } 'fixture frame recorder started'
        }
        $ledger = @()
        foreach ($demo in @(@('%2', 1), @('%3', 2), @('%1', 0), @('%i', 0), @('gi', 0))) {
            $null = Select-NotrapView $Session $order 1
            if ($demo[0] -eq 'gi') { (Get-Edit (Get-Window $Session) '1016').SetFocus() }
            $at = [DateTime]::UtcNow.ToString('o')
            Send-Keys $Session $demo[0]
            $wanted = [int]$demo[1]
            $null = Wait-Until {
                $state = Read-Control $Session status
                if ($wanted -eq 0) { $state.current_view.inbox } else { -not $state.current_view.inbox -and $state.current_view.account -eq $order[$wanted - 1].account }
            } 'recorded shortcut destination'
            $ledger += @{ key = $demo[0]; utc = $at; current_view = (Read-Control $Session status).current_view }
        }
        $ledger | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'ticketProof.json')
        if ($recorder) {
            $recorder.Refresh()
            Assert-That (-not $recorder.HasExited) 'Recording ended before shortcut demonstration'
            Wait-Process -Id $recorder.Id -Timeout 30 -ErrorAction Stop
            $recorder.Refresh()
            Assert-That ($recorder.ExitCode -eq 0 -and (Test-Path $video) -and (Get-Item $video).Length -gt 10000) 'Fixture recording failed'
            @{ mode = 'video'; width = $captureWidth; height = $captureHeight; fps = 5; started = $recordStarted; finished = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'ticketProof-capture.json')
        } else {
            $null = Wait-Job -Job $captureJob -Timeout 35
            Assert-That ($captureJob.State -eq 'Completed') 'Fixture frame recording failed or timed out'
            Receive-Job -Job $captureJob -ErrorAction Stop | Out-Null
        }
    } finally {
        if ($recorder -and -not $recorder.HasExited) { Stop-Process -Id $recorder.Id; $recorder.WaitForExit() }
        if ($captureJob) {
            if ($captureJob.State -in @('Running', 'NotStarted')) { Stop-Job -Job $captureJob }
            $null = Wait-Job -Job $captureJob
            Remove-Job -Job $captureJob -Force
        }
    }
    $transitions | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'transitions.json')
    Hub-Pass $Session every-view-escape-alt
    Save-Screen $Session after
}
