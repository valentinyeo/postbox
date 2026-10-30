$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.messages.Count -eq 6 -and @($shown.messages | Where-Object { $_.id -eq 'GROUP-FIRST' -and $_.bubble[2] -gt $_.bubble[0] }).Count -eq 1
} 'six group messages painted'
$shown = Read-Control $session messages
$rows = @{}
foreach ($row in $shown.messages) { $rows[$row.id] = $row }
foreach ($messageId in @('GROUP-FIRST', 'GROUP-DAY', 'GROUP-OTHER')) {
    $row = $rows[$messageId]
    Assert-That ($row.sender_header[2] -gt $row.sender_header[0]) "Group sender name missing: $messageId"
}
foreach ($messageId in @('GROUP-SAME', 'GROUP-QUOTE', 'GROUP-OWN')) {
    $row = $rows[$messageId]
    Assert-That ($row.sender_header[2] -eq $row.sender_header[0]) "Unexpected group sender name: $messageId"
}
$condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'WacliMessageCanvas')
$canvas = (Get-Window $session).FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
$bounds = $canvas.Current.BoundingRectangle
$columnWidth = [Math]::Min(920, $bounds.Width - 32)
$columnLeft = [Math]::Floor(($bounds.Width - $columnWidth) / 2)
foreach ($messageId in @('GROUP-FIRST', 'GROUP-SAME', 'GROUP-DAY', 'GROUP-OTHER', 'GROUP-QUOTE')) {
    $row = $rows[$messageId]
    Assert-That ($row.bubble[0] -eq ($columnLeft + 42)) "Group continuation lost avatar gutter: $messageId"
}
Assert-That (($rows['GROUP-SAME'].bubble[1] - $rows['GROUP-FIRST'].bubble[3]) -eq 4) 'Same sender messages not tightly grouped'
Assert-That (($rows['GROUP-QUOTE'].bubble[2] - $rows['GROUP-QUOTE'].bubble[0]) -lt 100) 'Quoted short reply stretches across the screen'
Assert-That (($rows['GROUP-QUOTE'].quote_line[2] - $rows['GROUP-QUOTE'].quote_line[0]) -gt ($rows['GROUP-QUOTE'].bubble[2] - $rows['GROUP-QUOTE'].bubble[0])) 'Compact reply hides its original-message preview'
Assert-That ($rows['GROUP-OWN'].bubble[2] -eq ($columnLeft + $columnWidth)) 'Own group message is not right-aligned'
Save-Screen $session group-senders
$image = [Drawing.Bitmap]::new((Join-Path $Evidence 'group-senders.png'))
try {
    foreach ($messageId in @('GROUP-FIRST', 'GROUP-DAY', 'GROUP-OTHER')) {
        $row = $rows[$messageId]
        $x = [int]($bounds.Left + $row.sender_header[0] - 42 + 15)
        $y = [int]($bounds.Top + $row.sender_header[1] + 5)
        $tint = $image.GetPixel($x, $y)
        Assert-That (([Math]::Max($tint.R, [Math]::Max($tint.G, $tint.B)) - [Math]::Min($tint.R, [Math]::Min($tint.G, $tint.B))) -gt 30) "Group sender avatar missing: $messageId"
        $colored = 0
        for ($sy = [int]$row.sender_header[1]; $sy -lt [int]$row.sender_header[3]; $sy++) {
            for ($sx = [int]$row.sender_header[0]; $sx -lt [int]$row.sender_header[2]; $sx++) {
                $pixel = $image.GetPixel([int]$bounds.Left + $sx, [int]$bounds.Top + $sy)
                if (([Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B)) - [Math]::Min($pixel.R, [Math]::Min($pixel.G, $pixel.B))) -gt 30) { $colored++ }
            }
        }
        Assert-That ($colored -gt 5) "Group sender name has no colour: $messageId"
    }
} finally { $image.Dispose() }
$shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'group-senders.messages.json')
'GROUP_LAYOUT_OK: names, avatars, day reset, continuation, own alignment and short quoted reply' | Set-Content (Join-Path $Evidence 'group-layout.txt')
