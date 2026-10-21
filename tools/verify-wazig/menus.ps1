Add-Type -Path "$PSScriptRoot/menus.cs"

function Read-ScreenshotPixels([string]$Path) {
    $image = [Drawing.Bitmap]::new($Path)
    try {
        $rect = [Drawing.Rectangle]::new(0, 0, $image.Width, $image.Height)
        $bits = $image.LockBits($rect, [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            Assert-That ($bits.Stride -gt 0) 'Screenshot must have top-down pixels'
            $bytes = [byte[]]::new($bits.Stride * $image.Height)
            [Runtime.InteropServices.Marshal]::Copy($bits.Scan0, $bytes, 0, $bytes.Length)
            return @{ bytes = $bytes; width = $image.Width; height = $image.Height; stride = $bits.Stride }
        } finally { $image.UnlockBits($bits) }
    } finally { $image.Dispose() }
}

function Measure-Screenshot([string]$Path, $Rect, [int]$ScreenX, [int]$ScreenY, [int]$Inset) {
    $image = Read-ScreenshotPixels $Path
    [VerifyMenus]::Measure($image.bytes, $image.width, $image.height, $image.stride, $Rect, $ScreenX, $ScreenY, $Inset)
}

function Find-Popup($Session, [string]$Class) {
    [VerifyMenus]::Find($Session.pid, $Class)
}

function Wait-Popup($Session, [string]$Class) {
    Wait-Until { $handle = Find-Popup $Session $Class; if ($handle -ne [IntPtr]::Zero) { $handle } } "$Class popup in owned process"
}

function Click-Control($Session, [string]$Id, [bool]$Right = $false) {
    $control = Get-Edit (Get-Window $Session) $Id
    $rect = $control.Current.BoundingRectangle
    $x = [int]($rect.Left + $rect.Width / 2)
    $y = [int]($rect.Top + [Math]::Min(20, $rect.Height / 2))
    $null = Get-App $Session
    [VerifyMenus]::Click($Session.pid, $x, $y, $Right)
    Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: control=$Id right=$Right x=$x y=$y"
}

function Assert-PopupPixels($Session, [string]$Name, [IntPtr]$Handle, [bool]$Light = $false, [int]$Inset = 8) {
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $rect = [VerifyMenus]::Bounds($Handle)
    $measurement = Measure-Screenshot (Join-Path $Session.evidence "$Name.png") $rect $screen.Left $screen.Top $Inset
    $record = [ordered]@{
        screenshot = "$Name.png"; expected = $(if ($Light) { 'light' } else { 'dark' })
        handle = $Handle.ToInt64(); screen = @{ left = $screen.Left; top = $screen.Top }
        measurement = $measurement; darkMaximum = 0.05126945837404324; lightMinimum = 0.7; contrastMinimum = 4.5
    }
    $script:menuMeasurements += $record
    $script:menuMeasurements | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'menu-luminances.json')
    [VerifyMenus]::Validate($measurement, $Light)
}

function Capture-Popup($Session, [string]$Name, [string]$Class, [bool]$Light = $false) {
    $handle = Wait-Popup $Session $Class
    $null = Wait-Until {
        Save-Screen $Session "$Name-after"
        $screen = [Windows.Forms.SystemInformation]::VirtualScreen
        $metric = Measure-Screenshot (Join-Path $Session.evidence "$Name-after.png") ([VerifyMenus]::Bounds($handle)) $screen.Left $screen.Top 8
        $metric.textPixels -ge 24
    } "$Name painted text"
    Assert-PopupPixels $Session "$Name-after" $handle $Light
    return $handle
}

function Close-Popup($Session, [string]$Class, [string]$Keys = '{ESC}') {
    Send-Keys $Session $Keys
    $null = Wait-Until { (Find-Popup $Session $Class) -eq [IntPtr]::Zero } "$Class closed"
}

function Open-PaletteCommand($Session, [string]$Command) {
    Send-Keys $Session '^k'
    $null = Wait-Popup $Session 'MessagesPalette'
    Send-Keys $Session $Command
    Send-Keys $Session '{ENTER}'
}

function Invoke-Menus($Session) {
    $script:menuMeasurements = @()
    [VerifyMenus]::TestOracle()
    'PIXEL ORACLE PASSED: readable dark/light controls accepted; swapped themes and blank text rejected' | Set-Content (Join-Path $Session.evidence 'pixel-oracle-controls.txt')
    Assert-That ((Read-Control $Session status).theme -eq 'amoled') 'Menus must start in default AMOLED'
    $loaded = Read-Control $Session messages
    Assert-That ($loaded.messages.Count -eq 1 -and $loaded.messages[0].id -eq 'verify-menu-message') 'Synthetic message cache did not load'
    foreach ($entry in @(@{ name = 'chat'; id = '1016' }, @{ name = 'composer'; id = '1032' }, @{ name = 'search'; id = '1008' })) {
        if ($entry.name -eq 'composer') {
            Click-Control $Session '1032'
            Send-Keys $Session 'Menu draft'
        } elseif ($entry.name -eq 'search') {
            Send-Keys $Session '^f'
            Send-Keys $Session 'Verification'
            $null = Wait-Until { (Read-Control $Session status).search -eq 'Verification' } 'synthetic search text'
        }
        Save-Screen $Session "amoled-$($entry.name)-before"
        Click-Control $Session $entry.id $true
        $null = Capture-Popup $Session "amoled-$($entry.name)" '#32768'
        Close-Popup $Session '#32768'
        if ($entry.name -eq 'composer') { Send-Keys $Session '^a{BACKSPACE}' }
        if ($entry.name -eq 'search') {
            Send-Keys $Session '{ESC}'
            $null = Wait-Until { (Read-Control $Session status).search -eq '' } 'search restored'
        }
    }
    Save-Screen $Session 'amoled-message-before'
    $canvas = Get-Edit (Get-Window $Session) '1024'
    $canvasRect = [VerifyMenus]::Bounds([IntPtr]$canvas.Current.NativeWindowHandle)
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $image = Read-ScreenshotPixels (Join-Path $Session.evidence 'amoled-message-before.png')
    $point = [VerifyMenus]::MessageText($image.bytes, $image.stride, $canvasRect, $screen.Left, $screen.Top)
    [VerifyMenus]::Click($Session.pid, $point.X, $point.Y, $true)
    Add-Content (Join-Path $Session.evidence 'actions.log') 'SendInput: right-click synthetic message text'
    $null = Capture-Popup $Session 'amoled-message' '#32768'
    Close-Popup $Session '#32768'
    Save-Screen $Session 'amoled-selection-before'
    [VerifyMenus]::Drag($Session.pid, $point.X, $point.Y, $point.X + 120)
    [VerifyMenus]::Click($Session.pid, $point.X + 40, $point.Y, $true)
    Add-Content (Join-Path $Session.evidence 'actions.log') 'SendInput: drag-select synthetic message text and right-click'
    $selection = Capture-Popup $Session 'amoled-selection' '#32768'
    $menu = [Windows.Automation.AutomationElement]::FromHandle($selection)
    Assert-That ($menu.Current.Name -ne $null) 'Selection menu is not readable by UI Automation'
    $items = $menu.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
    Assert-That (@($items | Where-Object { $_.Current.Name -eq 'Copy selection' }).Count -eq 1) 'Text drag did not open the selection-specific menu'
    Close-Popup $Session '#32768'
    foreach ($entry in @(
        @{ name = 'palette'; command = ''; class = 'MessagesPalette' },
        @{ name = 'accounts'; command = 'Manage accounts'; class = 'MessagesPalette' },
        @{ name = 'emoji'; command = 'Insert emoji'; class = 'MessagesEmojiPicker' },
        @{ name = 'shortcuts'; command = 'Keyboard shortcuts'; class = 'MessagesShortcutHelp' },
        @{ name = 'slack-setup'; command = 'Slack sign-in settings'; class = 'SlackSetup' }
    )) {
        Save-Screen $Session "amoled-$($entry.name)-before"
        if ($entry.command) { Open-PaletteCommand $Session $entry.command } else { Send-Keys $Session '^k' }
        if ($entry.name -eq 'accounts') {
            $null = Wait-Until {
                $handle = Find-Popup $Session 'MessagesPalette'
                if ($handle -eq [IntPtr]::Zero) { return $false }
                $accountWindow = [Windows.Automation.AutomationElement]::FromHandle($handle)
                (Read-Edit (Get-Edit $accountWindow '1064')) -eq ''
            } 'accounts palette replaced command filter'
        }
        if ($entry.name -eq 'emoji') {
            $null = Wait-Popup $Session $entry.class
            Send-Keys $Session 'heart'
        }
        $popup = Capture-Popup $Session "amoled-$($entry.name)" $entry.class
        $window = [Windows.Automation.AutomationElement]::FromHandle($popup)
        $edits = $window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'Edit'))
        foreach ($edit in $edits) {
            $rect = [VerifyMenus]::Bounds([IntPtr]$edit.Current.NativeWindowHandle)
            $metric = Measure-Screenshot (Join-Path $Session.evidence "amoled-$($entry.name)-after.png") $rect $screen.Left $screen.Top 4
            $script:menuMeasurements += [ordered]@{ screenshot = "amoled-$($entry.name)-after.png"; expected = 'dark-edit'; automationId = $edit.Current.AutomationId; measurement = $metric }
            $script:menuMeasurements | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'menu-luminances.json')
            if ($entry.name -eq 'emoji') { [VerifyMenus]::Validate($metric, $false) }
            Assert-That ($metric.background -le 0.05126945837404324 -and $metric.lightTileFraction -le 0.02) "$($entry.name) has a light edit field"
        }
        if ($entry.class -eq 'SlackSetup') { Close-Popup $Session $entry.class '%{F4}' } else { Close-Popup $Session $entry.class }
    }
    Click-Control $Session '1032'
    Save-Screen $Session 'amoled-shortcode-before'
    Send-Keys $Session ':hea'
    $null = Capture-Popup $Session 'amoled-shortcode' 'MessagesShortcodePopup'
    Send-Keys $Session '^a{BACKSPACE}'
    $null = Wait-Until { (Find-Popup $Session 'MessagesShortcodePopup') -eq [IntPtr]::Zero } 'shortcode closed'
    Send-Keys $Session '^k'
    Send-Keys $Session 'Theme: Green'
    Save-Screen $Session 'theme-green-action'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { (Read-Control $Session status).theme -eq 'green' } 'green theme'
    $preferences = "HKCU:\Software\MessagesVerification\$($Session.id)\Software\Messages"
    Assert-That ((Get-ItemProperty $preferences).Theme -eq 0) 'Green preference was not saved'
    Save-Screen $Session 'green-chat-before'
    Click-Control $Session '1016' $true
    $null = Capture-Popup $Session 'green-chat' '#32768' $true
    Close-Popup $Session '#32768'
    Save-Screen $Session after
}
