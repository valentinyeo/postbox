Send-Keys $session '%1'
$null = Wait-Until { (Read-Control $session status).view -eq 'slack' } 'Slack sidebar'
Send-Keys $session '^{TAB}'
$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.chat.id -eq 'slack:fixture-mentions:channel' -and $shown.chat.provider -eq 'slack' -and
        $shown.messages.Count -eq 5 -and @($shown.messages | Where-Object { $_.bubble[2] -le $_.bubble[0] -or $_.bubble[3] -le $_.bubble[1] }).Count -eq 0
} 'Slack mention messages painted'
Save-Screen $session before
$shown = Read-Control $session messages
$shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'before.messages.json')
Save-Screen $session after
$shown = Read-Control $session messages
$shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'after.messages.json')
$rows = @{}
foreach ($row in $shown.messages) { $rows[$row.id] = $row }
Assert-That ($rows.Count -eq 5) 'Slack mention fixture rows changed'
Assert-That ($rows['MENTION-NAMED'].text -ceq '@Fixture Peer hello') 'Cached sender name was not used for the known mention'
Assert-That ($rows['MENTION-NAMED'].text -ceq "@$($rows['MENTION-NAMED'].sender) hello") 'Mention name disagrees with the sender line'
Assert-That ($rows['MENTION-UNKNOWN'].text -ceq '@someone joins later') 'Unknown Slack member must show @someone'
Assert-That ($rows['MENTION-LABELLED'].text -ceq '@Outside Guest thanks report') 'Labelled Slack mention or report link label changed'
Assert-That (($rows['MENTION-LABELLED'].links -join ',') -ceq 'https://example.org/report') 'Report link target changed'
Assert-That ($rows['MENTION-GUEST'].text -ceq '@Guest Person joins @Fixture Peer') 'Guest missing from the member list did not resolve'
Assert-That ($rows['MENTION-GUEST'].sender -ceq 'Guest Person') 'Guest mention disagrees with the sender line'
Assert-That ($rows['MENTION-CONNECT'].text -ceq '@Guest Person meets @Connect Person') 'Slack Connect name or upstream-resolved guest changed'
foreach ($stage in @('before', 'after')) {
    $snapshot = Get-Content (Join-Path $Evidence "$stage.messages.json") -Raw | ConvertFrom-Json
    $rendered = $snapshot
    foreach ($row in $rendered.messages) { $row.PSObject.Properties.Remove('sender_id') }
    $rendered | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence "$stage.rendered.json")
    $snapshotText = $rendered | ConvertTo-Json -Depth 12
    $uiaText = Get-Content (Join-Path $Evidence "$stage.uia.txt") -Raw
    Assert-That ($snapshotText -cnotmatch '<@|<https://') 'Raw Slack mention or link markup reached the rendered snapshot'
    Assert-That ($uiaText -cnotmatch '<@') 'Raw Slack mention markup reached UI Automation'
    foreach ($fixtureId in @('U4A59H6UT', 'UUNKNOWN99', 'UHIDDEN01', 'UEXT00001', 'WCONNECT01')) {
        Assert-That ($snapshotText -cnotmatch [regex]::Escape($fixtureId)) "Fixture Slack id $fixtureId reached the rendered snapshot"
        Assert-That ($uiaText -cnotmatch [regex]::Escape($fixtureId)) "Fixture Slack id $fixtureId reached UI Automation"
    }
}
Hub-Pass $session mention-display
