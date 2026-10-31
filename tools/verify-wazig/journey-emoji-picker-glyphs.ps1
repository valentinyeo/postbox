Add-Type -Path "$PSScriptRoot/inline-links-native.cs"

function Assert-EmojiForeground($Session, $Window) {
    $null = Get-App $Session
    $handle = [IntPtr]$Window.Current.NativeWindowHandle
    $foreground = [VerifyWindow]::GetForegroundWindow()
    $owner = [uint32]0
    if ($foreground -ne [IntPtr]::Zero) { [VerifyWindow]::GetWindowThreadProcessId($foreground, [ref]$owner) | Out-Null }
    Assert-That ($foreground -eq $handle -and $owner -eq $Session.pid -and $Window.Current.ProcessId -eq $Session.pid) 'Keyboard target is not the owned window'
}

function Get-EmojiWindow($Session) {
    $owner = Get-Window $Session
    return Wait-Until {
        $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'MessagesEmojiPicker')
        $windows = $owner.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
        foreach ($window in $windows) { if ($window.Current.ProcessId -eq $Session.pid) { return $window } }
    } 'owned emoji picker'
}

$font = Get-Item (Join-Path $env:WINDIR 'Fonts/seguiemj.ttf')
@{ commit=$session.commit; sha256=$session.sha256; os=[Environment]::OSVersion.VersionString; font_file=$font.Name; font_version=$font.VersionInfo.FileVersion; font_sha256=(Get-FileHash $font.FullName).Hash; dpi=[VerifyWindow]::GetDpiForWindow((Get-App $session).MainWindowHandle) } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'emoji-environment.json')
$emojiOwnedApp = Get-App $session
$null = Wait-Until {
    [VerifyWindow]::SetForegroundWindow($emojiOwnedApp.MainWindowHandle) | Out-Null
    [VerifyWindow]::GetForegroundWindow() -eq $emojiOwnedApp.MainWindowHandle
} 'owned app foreground'
$window = Get-Window $session
Assert-EmojiForeground $session $window
[InlineLinksNative]::Combo(0x31)
Assert-EmojiForeground $session $window
[InlineLinksNative]::Combo(0x46)
Assert-EmojiForeground $session $window
[InlineLinksNative]::Combo(0x41)
Assert-EmojiForeground $session $window
[InlineLinksNative]::Text('Verification Inline WhatsApp')
$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.chat.id -ceq 'fixture-alpha' -and @($shown.messages | Where-Object id -CEQ 'INLINE-BODY').Count -eq 1
} 'synthetic chat loaded'
$chatPalette = Get-PaletteWindow $session
Assert-EmojiForeground $session $chatPalette
[InlineLinksNative]::Press(0x0D)
$null = Wait-Until {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'MessagesPalette')
    $palettes = $window.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
    $palettes.Count -eq 0 -and [VerifyWindow]::GetForegroundWindow() -eq $emojiOwnedApp.MainWindowHandle
} 'chat search closed and owned app foreground'
Assert-EmojiForeground $session $window
[InlineLinksNative]::Combo(0x4B)
$palette = Get-PaletteWindow $session
Assert-EmojiForeground $session $palette
[InlineLinksNative]::Text('Insert emoji')
$edit = Get-Edit $palette '1064'
$null = Wait-Until { (Read-Edit $edit) -ceq 'Insert emoji' } 'emoji palette query'
Assert-EmojiForeground $session $palette
[InlineLinksNative]::Press(0x0D)
$picker = Get-EmojiWindow $session
Assert-EmojiForeground $session $picker
$search = Get-Edit $picker '1088'
$null = Wait-Until { (Read-Edit $search) -ceq '' } 'empty emoji query'
$state = Read-Control $session status
$state | ConvertTo-Json -Depth 32 | Set-Content (Join-Path $session.evidence 'emoji-empty.status.json')
@{ session=$session.id; app_pid=$session.pid; popup=[long]$picker.Current.NativeWindowHandle; query=(Read-Edit $search) } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'emoji-empty.owner.json')
@(Read-BridgeRequests $session) | ConvertTo-Json -Depth 32 -AsArray | Set-Content (Join-Path $session.evidence 'emoji-empty.requests.json')
Save-Screen $session 'emoji-empty'
$cells = @($state.emoji_picker.cells)
Assert-That ($cells.Count -eq 48) 'Empty emoji grid must show 48 cells'
Assert-That ($cells[19].index -eq 11 -and $cells[19].text -ceq ([char]::ConvertFromUtf32(0x1FAEB))) 'Original target missing from row 3 column 4'
Assert-That (@($cells | Where-Object { $_.text -ceq ([char]::ConvertFromUtf32(0x1F44D)) -and $_.available }).Count -gt 0) 'Supported emoji positive control missing'
Assert-That (@($cells | Where-Object { -not $_.available }).Count -eq 0) 'Visible emoji lacks renderer support'
Assert-That (@(Read-BridgeRequests $session | Where-Object { $_.method -in @('POST','PUT','PATCH','DELETE') -and $_.wire_path -ne '/v1/wazig/mark-read' }).Count -eq 0) 'Unexpected mutating request'
