Invoke-PaletteCommand $session 'Theme: Graphite'
$null = Wait-Until { (Read-Control $session status).theme -eq 'amoled' } 'graphite chat theme'
foreach ($case in @(@{ provider = 'slack'; chat = 'fixture-alpha' }, @{ provider = 'whatsapp'; chat = 'fixture-beta' })) {
    $null = Read-Control $session select -Arguments @($case.chat, '--provider', $case.provider)
    $null = Wait-Until {
        $shown = Read-Control $session messages
        $main = @($shown.messages | Where-Object id -eq 'DESIGN-MAIN')
        $main.Count -eq 1 -and @($main[0].words).Count -gt 8
    } 'source-formatted messages painted'
    $shown = Read-Control $session messages
    $main = @($shown.messages | Where-Object id -eq 'DESIGN-MAIN')[0]
    $visible = @($main.words | ForEach-Object { $main.text.Substring($_.start, $_.len) })
    Assert-That (-not ($visible -contains '*Traffic*')) 'Visible markup: bold stars still painted'
    Assert-That ($visible -contains 'Traffic') 'Formatted title was not painted'
    Assert-That (@($main.words | Where-Object bold).Count -ge 3) 'Bold styles missing from painted words'
    Assert-That (@($main.words | Where-Object italic).Count -ge 2) 'Italic styles missing from painted words'
    Assert-That (@($main.words | Where-Object strike).Count -ge 1) 'Strikethrough missing from painted words'
    Assert-That (@($main.words | Where-Object mono).Count -ge 1) 'Inline monospace missing from painted words'
    Assert-That (@($main.words | Where-Object quote).Count -ge 4) 'Quote block missing from painted words'
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'WacliMessageCanvas')
    $canvas = (Get-Window $session).FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
    $bounds = $canvas.Current.BoundingRectangle
    $own = @($shown.messages | Where-Object id -eq 'DESIGN-OWN')[0]
    $long = @($shown.messages | Where-Object id -eq 'DESIGN-LONG')[0]
    $short = @($shown.messages | Where-Object id -eq 'DESIGN-SAME')[0]
    $columnWidth = [Math]::Min(920, $bounds.Width - 32)
    $columnLeft = [Math]::Floor(($bounds.Width - $columnWidth) / 2)
    $incomingLeft = $columnLeft + $(if ($case.provider -eq 'slack') { 42 } else { 0 })
    Assert-That ($main.bubble[0] -eq $incomingLeft -and $short.bubble[0] -eq $incomingLeft) 'Incoming messages left the centred column'
    Assert-That ($own.bubble[2] -eq ($columnLeft + $columnWidth) -and $long.bubble[2] -eq $own.bubble[2]) 'Own messages left the centred column'
    Assert-That (($short.bubble[2] - $short.bubble[0]) -lt ($main.bubble[2] - $main.bubble[0])) 'Short bubble did not hug its text'
    Assert-That (($own.bubble[2] - $own.bubble[0]) -lt 72) 'A tiny reply has an unrequested minimum width'
    Assert-That (($long.bubble[2] - $long.bubble[0]) -le 552) 'Long bubble exceeds the approved width'
    foreach ($row in $shown.messages) {
        foreach ($word in $row.words) {
            Assert-That ($word.rect[0] -ge $row.bubble[0] -and $word.rect[2] -le $row.bubble[2]) 'Painted text escapes its bubble'
        }
    }
    $name = "design-$($case.provider)"
    $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence "$name.messages.json")
    @{ x = $bounds.Left; y = $bounds.Top; width = $bounds.Width; height = $bounds.Height } | ConvertTo-Json | Set-Content (Join-Path $Evidence "$name.canvas.json")
    Save-Screen $session $name
    $image = [Drawing.Bitmap]::new((Join-Path $Evidence "$name.png"))
    try {
        $quote = @($main.words | Where-Object quote)[0]
        $sample = $image.GetPixel([int]($bounds.Left + $quote.rect[0] - 12), [int]($bounds.Top + $quote.rect[1] + 4))
        Assert-That ($sample.R -eq 74 -and $sample.G -eq 74 -and $sample.B -eq 74) 'Native quote bar does not match the approved grey'
    } finally { $image.Dispose() }
}
$null = Read-Control $session select -Arguments @('fixture-group@g.us', '--provider', 'whatsapp')
& "$PSScriptRoot/group-senders.ps1"
Invoke-PaletteCommand $session 'Theme: Graphite'
$null = Wait-Until { (Read-Control $session status).theme -eq 'amoled' } 'appearance journey final theme restored'
