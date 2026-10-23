. "$PSScriptRoot/menus.ps1"

function Invoke-ReactionsJourney($Session) {
    $source = Get-Content (Join-Path $PSScriptRoot '../../src/main.zig') -Raw
    $quick = [regex]::Match($source, 'const quick_reactions = \[_\]u16\{([^}]+)\}').Groups[1].Value.Split(',').Trim()
    $laughIndex = [Array]::IndexOf($quick, 'reaction_laugh')
    $emoji = [char]::ConvertFromUtf32(0x1f602)
    Assert-That ($laughIndex -ge 0 -and $source.Contains('reaction_laugh => "' + $emoji + '"')) 'Laughing-face source codepoints changed'
    $clicks = @()
    $failures = @()
    Send-Keys $Session '%0'
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
        $canvasRect = [VerifyMenus]::Bounds([IntPtr]$canvas.Current.NativeWindowHandle)
        $screen = [Windows.Forms.SystemInformation]::VirtualScreen
        $image = Read-ScreenshotPixels (Join-Path $Session.evidence "$name-message.png")
        $point = [VerifyMenus]::MessageText($image.bytes, $image.stride, $canvasRect, $screen.Left, $screen.Top)
        [VerifyMenus]::Click($Session.pid, $point.X, $point.Y, $true)
        Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: right-click $name message=$($target.message) x=$($point.X) y=$($point.Y)"
        $menu = Wait-Popup $Session '#32768'
        $popup = [VerifyMenus]::Bounds($menu)
        $menuElement = [Windows.Automation.AutomationElement]::FromHandle($menu)
        $items = $menuElement.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
        $reply = @($items | Where-Object { $_.Current.Name.StartsWith('Reply') })
        Assert-That ($reply.Count -eq 1) "$name message menu has no unique Reply row"
        $replyRect = $reply[0].Current.BoundingRectangle
        $dpi = [VerifyWindow]::GetDpiForWindow([IntPtr](Get-Window $Session).Current.NativeWindowHandle)
        $cell = [int][Math]::Floor((36 * $dpi + 48) / 96)
        $separator = [int][Math]::Floor((8 * $dpi + 48) / 96)
        $rowLeft = [int]$replyRect.Left
        $rowTop = [int]$replyRect.Bottom + $separator
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
    Save-Screen $Session after
}
