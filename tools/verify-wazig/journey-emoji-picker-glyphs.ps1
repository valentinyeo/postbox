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

function Open-EmojiPalette($Session, [string]$Command) {
    $window = Get-Window $Session
    Assert-EmojiForeground $Session $window
    [InlineLinksNative]::Combo(0x4B)
    $palette = Get-PaletteWindow $Session
    Assert-EmojiForeground $Session $palette
    [InlineLinksNative]::Text($Command)
    $edit = Get-Edit $palette '1064'
    $null = Wait-Until { (Read-Edit $edit) -ceq $Command } "palette query $Command"
    Assert-EmojiForeground $Session $palette
    [InlineLinksNative]::Press(0x0D)
    return Get-EmojiWindow $Session
}

function Capture-Emoji($Session, [string]$Name) {
    $state = Read-Control $Session status
    $state | ConvertTo-Json -Depth 32 | Set-Content (Join-Path $Session.evidence "emoji-$Name.status.json")
    @(Read-BridgeRequests $Session) | ConvertTo-Json -Depth 32 -AsArray | Set-Content (Join-Path $Session.evidence "emoji-$Name.requests.json")
    Save-Screen $Session "emoji-$Name"
    return $state
}

function Search-Emoji($Session, $Picker, [string]$Query) {
    Assert-EmojiForeground $Session $Picker
    [InlineLinksNative]::Combo(0x41)
    Assert-EmojiForeground $Session $Picker
    [InlineLinksNative]::Text($Query)
    $edit = Get-Edit $Picker '1088'
    $null = Wait-Until { (Read-Edit $edit) -ceq $Query } "emoji query $Query"
}

function Close-Emoji($Session, $Picker) {
    Assert-EmojiForeground $Session $Picker
    [InlineLinksNative]::Press(0x1B)
    $null = Wait-Until { $null -eq (Read-Control $Session status).emoji_picker } 'emoji picker closed'
}

$font = Get-Item (Join-Path $env:WINDIR 'Fonts/seguiemj.ttf')
@{ commit=$session.commit; sha256=$session.sha256; os=[Environment]::OSVersion.VersionString; font_file=$font.Name; font_version=$font.VersionInfo.FileVersion; font_sha256=(Get-FileHash $font.FullName).Hash; dpi=[VerifyWindow]::GetDpiForWindow((Get-App $session).MainWindowHandle) } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'emoji-environment.json')
$app = Get-App $session
$null = Wait-Until {
    [VerifyWindow]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
    [VerifyWindow]::GetForegroundWindow() -eq $app.MainWindowHandle
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
$picker = Open-EmojiPalette $session 'Insert emoji'
Assert-EmojiForeground $session $picker
$search = Get-Edit $picker '1088'
$null = Wait-Until { (Read-Edit $search) -ceq '' } 'empty emoji query'
$empty = Capture-Emoji $session 'empty'
$cells = @($empty.emoji_picker.cells)
$seed = $empty.emoji_picker.seed
$journal = @($empty.emoji_picker.journal)
Assert-That ($cells.Count -eq 48) 'Empty emoji grid must show 48 cells'
Assert-That (@($cells | Where-Object coverage -CEQ 'missing').Count -eq 0) 'Visible grid contains a missing glyph'
Assert-That ($null -ne $seed) 'No definitively missing native glyph found'
$missing = @($journal | Where-Object { $_.index -eq $seed -and $_.coverage -ceq 'missing' -and $_.missing })
Assert-That ($missing.Count -gt 0 -and $empty.emoji_picker.recents[0] -eq $seed) 'Seed was not an actual missing recent'
Assert-That (@($cells | Where-Object index -EQ $seed).Count -eq 0) 'Missing recent or catalog entry remained visible'
$target = @($journal | Where-Object index -EQ 11)[0]
if ($target.coverage -ceq 'missing') { Assert-That (@($cells | Where-Object index -EQ 11).Count -eq 0) 'Missing original target remained visible' }
$actualOrder = @($cells | Select-Object -Skip 8 | ForEach-Object index)
Assert-That (($actualOrder -join ',') -ceq ((@($actualOrder | Sort-Object) -join ','))) 'Catalog order changed'
foreach ($neighbor in @($journal | Where-Object { $_.index -ge 9 -and $_.index -le 13 -and $_.coverage -ceq 'supported' })) {
    Assert-That ($neighbor.index -in $actualOrder) 'Supported original neighbor missing'
}
Search-Emoji $session $picker $missing[0].name
$missingState = Capture-Emoji $session 'missing-search'
Assert-That (@($missingState.emoji_picker.cells | Where-Object index -EQ $seed).Count -eq 0) 'Missing emoji remained searchable'
if ($seed -eq 11) {
    Assert-That ($missingState.emoji_picker.match_count -eq 0) 'Missing target search was not empty'
    Assert-EmojiForeground $session $picker
    [InlineLinksNative]::Press(0x0D)
    $afterMissing = Capture-Emoji $session 'missing-enter'
    Assert-That ($null -ne $afterMissing.emoji_picker -and $afterMissing.emoji_picker.match_count -eq 0) 'Empty search activated an emoji'
}
Close-Emoji $session $picker
$compose = Get-Edit (Get-Window $session) '1032'
$picker = Open-EmojiPalette $session 'Insert emoji'
Search-Emoji $session $picker 'red heart'
$heartState = Capture-Emoji $session 'heart-search'
$heartText = [string]([char]0x2764) + [char]0xFE0F
$heart = @($heartState.emoji_picker.cells | Where-Object { $_.text -ceq $heartText })
Assert-That ($heart.Count -eq 1 -and $heart[0].coverage -ceq 'supported') 'Heart variation sequence unavailable'
$rect = $heart[0].rect
Assert-EmojiForeground $session $picker
[InlineLinksNative]::Click($session.pid, [int](($rect[0]+$rect[2])/2), [int](($rect[1]+$rect[3])/2))
$null = Wait-Until { (Read-Edit $compose) -ceq $heartText } 'exact heart inserted'
@{ text=(Read-Edit $compose); expected=$heartText } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'emoji-heart-insert.json')
$picker = Open-EmojiPalette $session 'Insert emoji'
Search-Emoji $session $picker 'winking face'
$winkState = Capture-Emoji $session 'wink-search'
$wink = [char]::ConvertFromUtf32(0x1F609)
Assert-That ($winkState.emoji_picker.cells[0].text -ceq $wink -and $winkState.emoji_picker.cells[0].coverage -ceq 'supported') 'Wink first result unavailable'
Assert-EmojiForeground $session $picker
[InlineLinksNative]::Press(0x0D)
$draft = $heartText + $wink
$null = Wait-Until { (Read-Edit $compose) -ceq $draft } 'exact wink inserted'
@{ text=(Read-Edit $compose); expected=$draft } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'emoji-wink-insert.json')
$picker = Open-EmojiPalette $session 'Insert emoji'
$recent = Capture-Emoji $session 'recent'
Assert-That ($recent.emoji_picker.cells[0].text -ceq $wink -and $recent.emoji_picker.cells[1].text -ceq $heartText) 'Recent canonical mapping changed'
Assert-That ($seed -in $recent.emoji_picker.recents -and @($recent.emoji_picker.cells | Where-Object index -EQ $seed).Count -eq 0) 'Missing recent was removed or displayed'
Close-Emoji $session $picker
Assert-That ((Read-Edit $compose) -ceq $draft) 'Compose cancel changed draft'
$window = Get-Window $session
Assert-EmojiForeground $session $window
[InlineLinksNative]::Combo(0x52)
$picker = Get-EmojiWindow $session
$reaction = Capture-Emoji $session 'reaction-cancel'
Assert-That $reaction.emoji_picker.react 'Reaction picker did not open'
Close-Emoji $session $picker
$final = Read-Control $session status
$requests = @(Read-BridgeRequests $session)
@{ draft=(Read-Edit $compose); expected=$draft; status=$final; requests=$requests } | ConvertTo-Json -Depth 32 | Set-Content (Join-Path $session.evidence 'emoji-final.json')
Assert-That ((Read-Edit $compose) -ceq $draft) 'Reaction cancel changed draft'
Assert-That (@($requests | Where-Object { $_.method -in @('POST','PUT','PATCH','DELETE') }).Count -eq 0) 'Unexpected mutating request'
