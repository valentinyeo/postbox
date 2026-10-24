Save-Screen $session before
Send-Keys $session '%1'
$null = Wait-Until { (Read-Control $session status).view -eq 'slack' } 'Slack sidebar'
Send-Keys $session '^{TAB}'
$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.chat.id -eq 'slack:fixture-mentions:channel' -and $shown.chat.provider -eq 'slack' -and
        $shown.messages.Count -eq 3 -and @($shown.messages | Where-Object { $_.bubble[2] -le $_.bubble[0] -or $_.bubble[3] -le $_.bubble[1] }).Count -eq 0
} 'Slack mention messages painted'
Save-Screen $session after
$shown = Read-Control $session messages
$shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'after.messages.json')
$rows = @{}
foreach ($row in $shown.messages) { $rows[$row.id] = $row }
Assert-That ($rows.Count -eq 3) 'Slack mention fixture rows changed'
Assert-That ($rows['MENTION-NAMED'].text -ceq '@Fixture Peer hello') 'Hub-resolved mention changed'
Assert-That ($rows['MENTION-UNKNOWN'].text -ceq '@someone joins later') 'Unknown Slack member must show @someone'
Assert-That ($rows['MENTION-LABELLED'].text -ceq '@Outside Guest thanks report') 'Labelled Slack mention or report link label changed'
Assert-That (($rows['MENTION-LABELLED'].links -join ',') -ceq 'https://example.org/report') 'Report link target changed'
Assert-That (($shown | ConvertTo-Json -Depth 12) -notmatch 'UUNKNOWN99|UHIDDEN01|<@|<https://') 'Raw Slack mention id or link markup reached the message pane'
Assert-That ((Get-Content (Join-Path $Evidence 'after.uia.txt') -Raw) -notmatch 'UUNKNOWN99|UHIDDEN01') 'Raw Slack mention id reached UI Automation'
Hub-Pass $session mention-display
