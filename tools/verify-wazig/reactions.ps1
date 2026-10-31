. "$PSScriptRoot/menus.ps1"

function Invoke-ReactionsJourney($Session) {
    $source = Get-Content (Join-Path $PSScriptRoot '../../src/main.zig') -Raw
    $quick = [regex]::Match($source, 'const quick_reactions = \[_\]u16\{([^}]+)\}').Groups[1].Value.Split(',').Trim()
    $laughIndex = [Array]::IndexOf($quick, 'reaction_laugh')
    $emoji = [char]::ConvertFromUtf32(0x1f602)
    Assert-That ($laughIndex -ge 0 -and $source.Contains('reaction_laugh => "' + $emoji + '"')) 'Laughing-face source codepoints changed'
    $clicks = @()
    $failures = @()
    Send-Keys $Session '%1'
    foreach ($target in @(
        @{ provider = 'whatsapp'; chat = 'fixture-beta'; message = 'BASELINE_BETA'; search = 'Verification Beta' },
        @{ provider = 'slack'; chat = 'fixture-alpha'; message = 'BASELINE'; search = 'Verification Alpha' }
    )) {
        $name = $target.provider
        Send-Keys $Session '^f'
        Send-Keys $Session $target.search
        $null = Wait-Until {
            $shown = Read-Control $Session messages
            $state = Read-Control $Session status
            $state.selected.id -eq $target.chat -and $state.selected.provider -eq $name -and
                $shown.chat.id -eq $target.chat -and @($shown.messages | Where-Object { $_.id -eq $target.message -and -not $_.from_me }).Count -eq 1
        } "$name incoming message visible"
        Click-Control $Session '1032'
        Save-Screen $Session "$name-message"
        $canvas = Get-Edit (Get-Window $Session) '1024'
        $incoming = Wait-Until {
            (Read-Control $Session messages).messages | Where-Object { $_.id -eq $target.message -and $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[3] -gt $_.bubble[1] }
        } "$name incoming bubble painted"
        $point = [VerifyWindow+Point]::new()
        $point.X = [int](($incoming.bubble[0] + $incoming.bubble[2]) / 2)
        $point.Y = [int](($incoming.bubble[1] + $incoming.bubble[3]) / 2)
        Assert-That ([VerifyWindow]::ClientToScreen([IntPtr]$canvas.Current.NativeWindowHandle, [ref]$point)) "$name canvas screen origin unavailable"
        [VerifyMenus]::Click($Session.pid, $point.X, $point.Y, $true)
        Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: right-click $name message=$($target.message) x=$($point.X) y=$($point.Y)"
        $menu = Wait-Popup $Session '#32768'
        $popup = [VerifyMenus]::Bounds($menu)
        $menuElement = [Windows.Automation.AutomationElement]::FromHandle($menu)
        $client = [VerifyWindow+Rect]::new()
        $origin = [VerifyWindow+Point]::new()
        Assert-That ([VerifyWindow]::GetClientRect($menu, [ref]$client)) "$name menu client bounds unavailable"
        Assert-That ([VerifyWindow]::ClientToScreen($menu, [ref]$origin)) "$name menu screen origin unavailable"
        $dpi = [VerifyWindow]::GetDpiForWindow([IntPtr](Get-Window $Session).Current.NativeWindowHandle)
        $cell = [int][Math]::Floor((36 * $dpi + 48) / 96)
        $separator = [int][Math]::Floor((8 * $dpi + 48) / 96)
        $textRowsHeight = $client.Bottom - $cell - 3 * $separator
        Assert-That ($textRowsHeight -gt 0 -and $textRowsHeight % 4 -eq 0) "$name message menu row layout changed"
        $rowLeft = $origin.X
        $rowTop = $origin.Y + [int]($textRowsHeight / 4) + $separator
        $x = $popup.Left + ($rowLeft - $popup.Left) + $laughIndex * $cell + [int][Math]::Floor($cell / 2)
        $y = $popup.Top + ($rowTop - $popup.Top) + [int][Math]::Floor($cell / 2)
        Assert-That ($x -gt $popup.Left -and $x -lt $popup.Right -and $y -gt $popup.Top -and $y -lt $popup.Bottom) "$name laughing cell outside menu"
        $clicks += @{ provider = $name; chat = $target.chat; message = $target.message; menu_class = '#32768'; menu_pid = $menuElement.Current.ProcessId; menu = $popup; row_left = $rowLeft; row_top = $rowTop; cell_width = $cell; index = $laughIndex; x = $x; y = $y; expected = $emoji }
        ConvertTo-Json -InputObject $clicks -Depth 12 | Set-Content (Join-Path $Session.evidence 'reaction-clicks.json')
        Save-Screen $Session "$name-before"
        [VerifyMenus]::Click($Session.pid, $x, $y, $false)
        Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: left-click $name laughing-face cell=$laughIndex x=$x y=$y"
        $null = Wait-Until { (Find-Popup $Session '#32768') -eq [IntPtr]::Zero } "$name menu closed"
        $path = Join-Path $Session.evidence 'react-requests.jsonl'
        $request = Wait-Until {
            if (-not (Test-Path $path)) { return $false }
            Get-Content $path | Where-Object { $_.EndsWith('}') } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.chat -eq $target.chat -and $_.msg -eq $target.message } | Select-Object -Last 1
        } "$name hub reaction request"
        $actual = $request.emoji
        $null = Wait-Until {
            @((Read-Control $Session messages).messages | Where-Object { $_.id -eq $target.message -and $_.reaction -ceq $actual }).Count -eq 1
        } "$name received reaction shown"
        Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$name-after.messages.json")
        Save-Screen $Session "$name-after"
        if ($actual -cne $emoji) {
            $failure = "REACTION MISMATCH: $name chat=$($target.chat) expected $emoji (U+1F602), received $actual"
            Write-Host $failure
            Add-Content (Join-Path $Session.evidence 'actions.log') $failure
            $failures += $failure
        } else {
            Hub-Pass $Session "$name-laughing-face"
        }
        Send-Keys $Session '^f'
        Send-Keys $Session '^a{BACKSPACE}'
        Send-Keys $Session '{ESC}'
    }
    Assert-That ($failures.Count -eq 0) ($failures -join '; ')
    Send-Keys $Session '^f'
    Send-Keys $Session 'Verification Beta'
    $heart = [char]::ConvertFromUtf32(0x2764) + [string][char]0xfe0f
    $null = Wait-Until {
        $shown = Read-Control $Session messages
        $shown.chat.id -eq 'fixture-beta' -and $shown.chat.provider -eq 'whatsapp' -and
            @($shown.messages | Where-Object { $_.id -eq 'CHIP' -and $_.reaction.Contains($heart) }).Count -eq 1
    } 'CHIP friend heart visible'
    Click-Control $Session '1032'
    foreach ($phase in @('added', 'removed')) {
        $chip = Wait-Until {
            (Read-Control $Session messages).messages | Where-Object { $_.id -eq 'CHIP' -and $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[3] -gt $_.bubble[1] }
        } 'CHIP bubble painted'
        $canvas = Get-Edit (Get-Window $Session) '1024'
        $handle = [IntPtr]$canvas.Current.NativeWindowHandle
        $dpi = [VerifyWindow]::GetDpiForWindow($handle)
        $point = [VerifyWindow+Point]::new()
        $rect = @($chip.reaction_chip)
        if ($rect.Count -eq 4 -and $rect[2] -gt $rect[0] -and $rect[3] -gt $rect[1]) {
            $point.X = [int](($rect[0] + $rect[2]) / 2)
            $point.Y = [int](($rect[1] + $rect[3]) / 2)
        } else {
            $point.X = [int]$chip.bubble[0] + [int][Math]::Floor((24 * $dpi + 48) / 96)
            $point.Y = [int]$chip.bubble[3] + [int][Math]::Floor((8 * $dpi + 48) / 96)
        }
        Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$point)) 'CHIP canvas screen origin unavailable'
        [VerifyMenus]::Click($Session.pid, $point.X, $point.Y, $false)
        Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: left-click CHIP $phase x=$($point.X) y=$($point.Y)"
        $expected = if ($phase -eq 'added') { $heart } else { '' }
        try {
            $null = Wait-Until {
                if (-not (Test-Path $path)) { return $false }
                Get-Content $path | Where-Object { $_.EndsWith('}') } | ForEach-Object { $_ | ConvertFrom-Json } |
                    Where-Object { $_.chat -eq 'fixture-beta' -and $_.msg -eq 'CHIP' -and $_.emoji -ceq $expected } | Select-Object -Last 1
            } "CHIP $phase hub reaction request"
        } catch {
            $operation = if ($phase -eq 'added') { 'add' } else { 'remove' }
            throw "CHIP REACTION MISSING: $operation did not reach the hub"
        }
        $shown = Wait-Until {
            $messages = Read-Control $Session messages
            if (@($messages.messages | Where-Object { $_.id -eq 'CHIP' -and $_.reaction.Contains($heart) -and $_.my_reaction -ceq $expected }).Count -eq 1) { return $messages }
        } "CHIP $phase own reaction and friend heart"
        $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "chip-$phase.messages.json")
        Save-Screen $Session "chip-$phase"
        Hub-Pass $Session "chip-$phase"
    }
    Save-Screen $Session after
}
