. "$PSScriptRoot/search-proof.ps1"
$queryPath = Join-Path $PSScriptRoot 'search-queries.json'
Copy-Item $queryPath (Join-Path $Evidence 'search-queries.json')
$fixture = Get-Content $queryPath -Raw | ConvertFrom-Json
$baseline = $null -ne (Find-SidebarSearch $session)
$proof = @{ schema = 1; baseline = $baseline; commit = $session.commit; sha256 = $session.sha256; query_sha256 = (Get-FileHash $queryPath).Hash; records = @() }
foreach ($case in $fixture.queries) {
    $state = Read-Control $session status
    if ($state.show_archived -ne [bool]$case.archived_only) {
        Invoke-PaletteCommand $session $(if ($case.archived_only) { 'Show archived chats' } else { 'Show inbox chats' })
    }
    if ((Read-Control $session status).unread_only -ne [bool]$case.unread_only) { Invoke-PaletteCommand $session 'Toggle unread chats' }
    $emptyStart = (Read-Control $session status).chat_count -eq 0
    $samples = @()
    foreach ($shortcut in @('^f', '/')) {
        $samples += Read-SearchSample $session $case.query $shortcut $baseline
        if ($case.query -ceq 'Beta' -and $shortcut -ceq '^f') { Save-Screen $session search-match }
        if ($case.category -ceq 'no-match' -and $shortcut -ceq '^f') { Save-Screen $session empty }
        Send-Keys $session '{ESC}'
        $null = Wait-Until { (Read-Control $session status).search -ceq '' } 'search clears after replay'
    }
    Assert-That (($samples[0].identities -join "`n") -ceq ($samples[1].identities -join "`n")) "Search order differs between shortcuts: $($case.query)"
    $proof.records += @{ case = $case; empty_start = $emptyStart; samples = $samples }
    $proof | ConvertTo-Json -Depth 18 | Set-Content (Join-Path $Evidence 'search-parity.json')
}
if ((Read-Control $session status).unread_only) { Invoke-PaletteCommand $session 'Toggle unread chats' }
$window = Get-Window $session
$handle = [IntPtr]$window.Current.NativeWindowHandle
$origin = [VerifyWindow+Point]::new()
Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'Cannot locate search layout'
$elements = $window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
$list = Get-Edit $window '1016'
$removal = @{
    controls = @($elements | Where-Object { $_.Current.AutomationId -eq '1008' }).Count
    native = ([VerifyWindow]::GetDlgItem($handle, 1008) -ne [IntPtr]::Zero)
    labels = @($elements | ForEach-Object { $_.Current.Name } | Where-Object { $_ -match 'Search All|Search chats  Ctrl\+F|Search .+  Ctrl\+F' })
    list_top = $list.Current.BoundingRectangle.Top; client_top = $origin.Y
}
$removal | ConvertTo-Json | Set-Content (Join-Path $Evidence 'search-removal.json')
Assert-That (-not $baseline -and $removal.controls -eq 0 -and -not $removal.native -and $removal.labels.Count -eq 0) 'Sidebar search bar remains; baseline parity was captured before this intentional red assertion'
Assert-That ([Math]::Abs($removal.list_top - $removal.client_top) -le 1) 'Search layout slot remains'
Assert-PaletteSearchShortcuts $session
Save-PaletteArchiveInk $session
. "$PSScriptRoot/journey-palette.ps1"
