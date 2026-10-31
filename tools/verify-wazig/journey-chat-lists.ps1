. "$PSScriptRoot/menus.ps1"
Set-DisplayResolution -Width 1280 -Height 1024 -Force
$null = Wait-Until { [Windows.Forms.SystemInformation]::VirtualScreen.Height -ge 1024 } 'list desktop fits both approved text sizes'
[VerifyWindow]::ShowWindow((Get-App $session).MainWindowHandle, 3) | Out-Null

function Get-ListInkLeft($Image, $Rect, [int]$OriginX, [int]$OriginY) {
    $found = $Image.width
    for ($y = $OriginY + $Rect[1]; $y -lt $OriginY + $Rect[3]; $y++) {
        for ($x = $OriginX + $Rect[0]; $x -lt $OriginX + $Rect[2]; $x++) {
            Assert-That ($x -ge 0 -and $x -lt $Image.width -and $y -ge 0 -and $y -lt $Image.height) 'List word is outside the screenshot'
            $at = $y * $Image.stride + $x * 4
            if ([int]$Image.bytes[$at] + [int]$Image.bytes[$at + 1] + [int]$Image.bytes[$at + 2] -gt 600) {
                $found = [Math]::Min($found, $x)
            }
        }
    }
    Assert-That ($found -lt $Image.width) 'List word has no visible foreground ink'
    return $found - $OriginX
}

Send-Keys $session '%2'
Send-Keys $session '^{TAB}'
$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.chat.id -eq 'slack:fixture-lists:channel' -and $shown.messages.Count -eq 1 -and $shown.messages[0].words.Count -gt 8
} 'list fixture painted'
$checks = @()
foreach ($stage in @('baseline', 'larger')) {
    if ($stage -eq 'larger') { Invoke-PaletteCommand $session 'Make text larger' }
    $null = Wait-Until {
        $row = (Read-Control $session messages).messages[0]
        $row.words.Count -gt 8 -and ($stage -eq 'baseline' -or ($row.font_height -lt $baselineHeight -and $row.bubble[1] -lt $baselineTop -and $row.words[-1].rect[1] -ne $baselineLastTop))
    } "$stage list font and layout"
    $row = (Read-Control $session messages).messages[0]
    Assert-That ($row.body_weight -eq 400) 'Ordinary message body must use Regular weight'
    if ($stage -eq 'baseline') { $baselineHeight = $row.font_height; $baselineTop = $row.bubble[1]; $baselineLastTop = $row.words[-1].rect[1] }
    $canvas = Get-Edit (Get-Window $session) '1024'
    $bounds = $canvas.Current.BoundingRectangle
    Assert-That ($row.bubble[1] -ge 0 -and $row.bubble[3] -le $bounds.Height) 'The complete list bubble must be visible and fit its measured height'
    Save-Screen $session $stage
    $row | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence "$stage.messages.json")
    $image = Read-ScreenshotPixels (Join-Path $Evidence "$stage.png")
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $originX = [int]$bounds.Left - $screen.Left
    $originY = [int]$bounds.Top - $screen.Top
    $offset = 0
    $items = @()
    foreach ($line in $row.text.Split("`n")) {
        $lineWords = @($row.words | Where-Object { $_.start -ge $offset -and $_.start -lt $offset + $line.Length })
        Assert-That ($lineWords.Count -eq 21) 'Each list item must retain its marker and all twenty words'
        $marker = $lineWords[0]
        $first = $lineWords[1]
        $textX = [int]$first.rect[0]
        $markerX = [int]$marker.rect[0]
        Assert-That ($textX -gt $markerX) 'List text must start after its marker column'
        $firstInk = Get-ListInkLeft $image $first.rect $originX $originY
        $continuations = @()
        $previousY = $first.rect[1]
        foreach ($word in $lineWords[2..($lineWords.Count - 1)]) {
            Assert-That ($word.rect[3] -le $row.bubble[3]) 'List text clips below the measured bubble'
            if ($word.rect[1] -ne $previousY) {
                $ink = Get-ListInkLeft $image $word.rect $originX $originY
                Assert-That ($word.rect[0] -eq $textX -and $word.rect[0] -gt $markerX) 'Wrapped text must align under its first-line text, not the marker'
                Assert-That ([Math]::Abs($ink - $firstInk) -le 1) 'Wrapped-line foreground ink differs from the first-line text edge by more than one pixel'
                $continuations += @{ x = [int]$word.rect[0]; ink_x = $ink; y = [int]$word.rect[1] }
            }
            $previousY = $word.rect[1]
        }
        Assert-That ($continuations.Count -gt 0) 'Every fixture list item must wrap'
        $items += @{ marker_x = $markerX; text_x = $textX; ink_x = $firstInk; continuations = $continuations }
        $offset += $line.Length + 1
    }
    Assert-That ($items.Count -eq 8 -and $items[6].text_x -gt $items[5].text_x -and $items[7].text_x -gt $items[6].text_x) 'Nested list levels must step inward'
    $checks += @{ stage = $stage; body_weight = $row.body_weight; font_height = $row.font_height; items = $items }
    ConvertTo-Json -InputObject $checks -Depth 12 | Set-Content (Join-Path $Evidence 'list-alignment.json')
}
Send-Keys $session '^0'
Save-Screen $session after
Hub-Pass $session hanging-indent-and-regular-weight
