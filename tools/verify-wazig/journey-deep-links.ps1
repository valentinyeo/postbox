Add-Type -Path "$PSScriptRoot/menus.cs"

function Invoke-PostboxLink($Session, [string]$Link) {
    $psi = [Diagnostics.ProcessStartInfo]::new($Session.exe)
    $psi.UseShellExecute = $false
    $psi.ArgumentList.Add($Link)
    $psi.Environment['LOCALAPPDATA'] = Join-Path $Session.root 'local'
    $psi.Environment['APPDATA'] = Join-Path $Session.root 'local'
    $psi.Environment['USERPROFILE'] = Join-Path $Session.root 'profile'
    $psi.Environment['USERNAME'] = $Session.username
    $child = [Diagnostics.Process]::Start($psi)
    try {
        Assert-That ($child.WaitForExit(10000)) "Forwarder process timed out for $Link"
        Assert-That ($child.ExitCode -eq 0) "Forwarder process failed with exit $($child.ExitCode) for $Link"
    } finally {
        if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
        $child.Dispose()
    }
    Add-Content (Join-Path $Session.evidence 'actions.log') "link: $Link"
}

$protocolRoot = "HKCU:\Software\MessagesVerification\$($session.id)\Software\Classes\postbox"
Assert-That (Test-Path $protocolRoot) 'postbox protocol registry key missing'
$rootProps = Get-ItemProperty $protocolRoot
$cmdProps = Get-ItemProperty "$protocolRoot\shell\open\command"
$expectedCommand = "`"$($session.exe)`" `"%1`""
Assert-That ($rootProps.'(default)' -ceq 'URL:Postbox Protocol') 'Protocol description mismatch'
Assert-That ($rootProps.'URL Protocol' -ceq '') 'URL Protocol marker missing'
Assert-That ($cmdProps.'(default)' -ceq $expectedCommand) 'Protocol open command mismatch'

Invoke-PostboxLink $session 'postbox://whatsapp/business/15550000101@s.whatsapp.net'
$waState = Wait-Until {
    $observed = Read-Control $session status
    if ($observed.selected.id -ceq 'business:15550000101@s.whatsapp.net' -and $observed.selected.provider -ceq 'whatsapp' -and $observed.selected.view_account -ceq 'business') { $observed }
} 'WhatsApp business chat opened by link'
$null = Wait-Until {
    @((Read-Control $session messages).messages | Where-Object { $_.id -ceq 'business:BIZ-MSG-09' -and $_.bubble[2] -gt $_.bubble[0] }).Count -eq 1
} 'WhatsApp business chat painted'
Save-Screen $session whatsapp-link

Invoke-PostboxLink $session 'postbox://slack/T0ALPHA1/C0LAUNCH1/p1700000005000100'
$slackState = Wait-Until {
    $observed = Read-Control $session status
    if ($observed.selected.id -ceq 'slack:T0ALPHA1:C0LAUNCH1' -and $observed.selected.provider -ceq 'slack' -and $observed.selected.view_account -ceq 'T0ALPHA1' -and $observed.scroll_y -gt 0) { $observed }
} 'Slack chat opened and scrolled by link'
$canvas = [IntPtr](Get-Edit (Get-Window $session) '1024').Current.NativeWindowHandle
$canvasRect = [VerifyWindow+Rect]::new()
Assert-That ([VerifyWindow]::GetClientRect($canvas, [ref]$canvasRect)) 'Slack canvas bounds missing'
$slackTarget = Wait-Until {
    (Read-Control $session messages).messages | Where-Object {
        $_.id -ceq '1700000005.000100' -and $_.selected -and $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[1] -ge 0 -and $_.bubble[3] -le $canvasRect.Bottom
    }
} 'Slack target message scrolled into view'
Save-Screen $session slack-link

$compose = Get-Edit (Get-Window $session) '1032'
$compose.SetFocus()
Send-Keys $session 'Keep draft unchanged'
$null = Wait-Until { (Read-Edit $compose) -ceq 'Keep draft unchanged' } 'Draft typed before missing link'
$beforeMissing = Read-Control $session status
$beforeMissingMessages = Read-Control $session messages

Invoke-PostboxLink $session 'postbox://whatsapp/business/99999999999@s.whatsapp.net'
$missingState = Wait-Until {
    Assert-That ([VerifyMenus]::Find($session.pid, '#32770') -eq [IntPtr]::Zero) 'Missing link opened a modal dialog'
    $observed = Read-Control $session status
    if ($observed.update_card.visible -and $observed.update_card.error -ceq 'Could not find that WhatsApp chat.') { $observed }
} 'Missing chat link shows clear note'
$afterMissingMessages = Read-Control $session messages
$afterDraft = Read-Edit $compose
Assert-That ($missingState.selected.id -ceq $beforeMissing.selected.id) 'Missing link changed selected chat'
Assert-That ($missingState.selected.provider -ceq $beforeMissing.selected.provider) 'Missing link changed provider'
Assert-That ($missingState.view -ceq $beforeMissing.view) 'Missing link changed view'
Assert-That ($missingState.search -ceq $beforeMissing.search) 'Missing link changed search'
Assert-That ($missingState.scroll_y -eq $beforeMissing.scroll_y) 'Missing link changed scroll position'
Assert-That ($afterDraft -ceq 'Keep draft unchanged') 'Missing link changed composer draft'
$stillSelected = @($afterMissingMessages.messages | Where-Object { $_.selected })
Assert-That ($stillSelected.Count -eq 1 -and $stillSelected[0].id -ceq '1700000005.000100') 'Missing link changed selected message'
Save-Screen $session missing-link

$windowHandle = [IntPtr](Get-Window $session).Current.NativeWindowHandle
$origin = [VerifyWindow+Point]::new()
Assert-That ([VerifyWindow]::ClientToScreen($windowHandle, [ref]$origin)) 'Window origin missing for dismiss'
$scale = [VerifyWindow]::GetDpiForWindow($windowHandle) / 96.0
$dismissX = [int]($origin.X + $missingState.update_card.rect[0] + 68 * $scale)
$dismissY = [int]($origin.Y + $missingState.update_card.rect[3] - 23 * $scale)
[VerifyMenus]::Click($session.pid, $dismissX, $dismissY, $false)
$null = Wait-Until {
    $observed = Read-Control $session status
    -not $observed.update_card.visible -and $observed.update_card.error -ceq ''
} 'Missing chat note dismissed cleanly'

$old = Get-App $session
Invoke-PaletteCommand $session 'Quit Postbox'
$null = Wait-Until { $old.Refresh(); $old.HasExited } 'App exited before cold-start link'

$cold = [Diagnostics.ProcessStartInfo]::new($session.exe)
$cold.UseShellExecute = $false
$cold.RedirectStandardError = $true
$cold.ArgumentList.Add('--verify-fixture')
$cold.ArgumentList.Add('postbox://whatsapp/personal/15550000101@s.whatsapp.net/WA-TARGET-MSG')
foreach ($entry in $start.Environment.GetEnumerator()) { $cold.Environment[$entry.Key] = $entry.Value }
$cold.Environment['WAZIG_VERIFY_RESTART'] = $session.id
$app = [Diagnostics.Process]::Start($cold)
$session.pid = $app.Id
$session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
$session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'session.json')
$null = Wait-Until { $app.Refresh(); if ($app.HasExited) { throw "Cold-start app exited: $($app.ExitCode)" }; $app.MainWindowHandle -ne [IntPtr]::Zero } 'cold-start main window' -Harness
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null

$coldState = Wait-Until {
    try {
        $observed = Read-Control $session status
        if ($observed.selected.id -ceq 'personal:15550000101@s.whatsapp.net' -and $observed.selected.provider -ceq 'whatsapp' -and $observed.scroll_y -gt 0) { $observed }
    } catch { $null }
} 'Closed Postbox started and opened WhatsApp chat scrolled to message' 40
$coldCanvas = [IntPtr](Get-Edit (Get-Window $session) '1024').Current.NativeWindowHandle
$coldCanvasRect = [VerifyWindow+Rect]::new()
Assert-That ([VerifyWindow]::GetClientRect($coldCanvas, [ref]$coldCanvasRect)) 'Cold-start canvas bounds missing'
$coldTarget = Wait-Until {
    (Read-Control $session messages).messages | Where-Object {
        $_.id -ceq 'personal:WA-TARGET-MSG' -and $_.selected -and $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[1] -ge 0 -and $_.bubble[3] -le $coldCanvasRect.Bottom
    }
} 'Cold-start WhatsApp target message scrolled into view'
Save-Screen $session cold-start-link

@{
    registry = @{
        description = $rootProps.'(default)'
        url_protocol = $rootProps.'URL Protocol'
        command = $cmdProps.'(default)'
        expected_command = $expectedCommand
    }
    whatsapp_link = @{
        selected = $waState.selected
    }
    slack_link = @{
        selected = $slackState.selected
        scroll_y = $slackState.scroll_y
        target_id = $slackTarget.id
        target_bubble = $slackTarget.bubble
        canvas_bottom = $canvasRect.Bottom
    }
    missing_link = @{
        error = $missingState.update_card.error
        before_selected = $beforeMissing.selected.id
        after_selected = $missingState.selected.id
        before_scroll = $beforeMissing.scroll_y
        after_scroll = $missingState.scroll_y
        draft = $afterDraft
        selected_message = $stillSelected[0].id
    }
    cold_start_link = @{
        selected = $coldState.selected
        scroll_y = $coldState.scroll_y
        target_id = $coldTarget.id
        target_bubble = $coldTarget.bubble
        canvas_bottom = $coldCanvasRect.Bottom
    }
} | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'deep-links.json')
