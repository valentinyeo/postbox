if ($session.feature -eq 'palette') {
    $launch = Get-Content (Join-Path $messages 'launch-log.txt') -Raw
    Assert-That ($launch.Contains('whatsapp backend: unavailable (URL not configured)') -and -not $launch.Contains('message backend: hub') -and -not $launch.Contains('whatsapp backend: hub') -and -not $launch.Contains('whatsapp backend: wacli')) 'Unconfigured hub did not stay unavailable'
    Add-Content (Join-Path $Evidence 'fallback-proof.log') 'hub no-url-unavailable PASS'
    . "$PSScriptRoot/search-proof.ps1"
    Assert-PaletteSearchShortcuts $session
}
Send-Keys $session '^k'
$palette = Get-PaletteWindow $session
Send-Keys $session 'Keyboard shortcuts'
$edit = Get-Edit $palette '1064'
$list = Get-Edit $palette '1072'
$null = Wait-Until { (Read-Edit $edit) -eq 'Keyboard shortcuts' -and (Read-ListCount $list) -eq 1 } 'positive palette row control'
$positiveRows = @(Read-ListLabels $list)
Assert-That ($positiveRows.Count -eq 1 -and $positiveRows[0] -eq 'Keyboard shortcuts') 'Positive palette row label is not readable'
$positiveCount = $positiveRows.Count
Send-Keys $session '^a'
Send-Keys $session 'Status'
$settled = @{ signature = $null; since = [DateTime]::UtcNow; rows = @() }
$null = Wait-Until {
    if ((Read-Edit $edit) -ne 'Status') { return $false }
    $settled.rows = @(Read-ListLabels $list)
    $signature = ConvertTo-Json -InputObject $settled.rows -Compress
    if ($signature -cne $settled.signature) {
        $settled.signature = $signature
        $settled.since = [DateTime]::UtcNow
        return $false
    }
    return ([DateTime]::UtcNow - $settled.since).TotalMilliseconds -ge 200
} 'removed Status query and settled palette rows'
$rows = $settled.rows
$statusCount = @($rows | Where-Object { $_.Trim() -ieq 'Status' }).Count
$removedCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, '1120')
$sidebarCount = $window.FindAll([Windows.Automation.TreeScope]::Descendants, $removedCondition).Count
@{ query = Read-Edit $edit; status_rows = $statusCount; rows = $rows; positive_query = 'Keyboard shortcuts'; positive_matches = $positiveCount; sidebar_status_controls = $sidebarCount } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'removed-status.json')
Save-Screen $session removed-status
Assert-That ($statusCount -eq 0 -and $sidebarCount -eq 0) 'Removed WhatsApp Status entry is still reachable'
Send-Keys $session '^a'
Send-Keys $session 'Keyboard shortcuts'
$null = Wait-Until { (Read-Edit $edit) -eq 'Keyboard shortcuts' -and (Read-ListCount $list) -eq 1 } 'shortcut command restored'
Save-Screen $session action
Send-Keys $session '{ENTER}'
$owner = Get-Window $session
$null = Wait-Until {
    $condition = [Windows.Automation.AndCondition]::new(
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'MessagesShortcutHelp'),
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty, [int]$session.pid)
    )
    $owner.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
} 'keyboard shortcut overlay'
Save-Screen $session after
Send-Keys $session '{ESC}'
