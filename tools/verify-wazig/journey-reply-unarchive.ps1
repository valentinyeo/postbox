. "$PSScriptRoot/menus.ps1"

function Select-ReplyChat($Session, [string]$Id) {
    $null = Wait-Until { try { (Read-Control $Session chats).chats | Where-Object { $_.id -ceq $Id } } catch { $false } } "$Id listed" 60
    $null = Read-Control $Session select -Arguments @($Id, '--provider', 'whatsapp')
    $null = Wait-Until { (Read-Control $Session status).selected.id -ceq $Id } "$Id selected" 30
}

function Send-ReplyMessage($Session, [string]$Text, [string]$Label) {
    $before = @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.status -eq 200 }).Count
    Click-Control $Session '1032'
    Send-Keys $Session $Text
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until {
        @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.status -eq 200 }).Count -eq $before + 1
    } "$Label send accepted by the hub" 30
    $null = Wait-Until { (Read-Control $Session status).pending_sends -eq 0 -and (Read-Control $Session status).pending_archives -eq 0 } "$Label outbox and archive queue empty" 60
}

function Test-ChatListed($Session, [string]$Id) {
    try { return [bool]((Read-Control $Session chats).chats.id -contains $Id) } catch { return $false }
}

Send-Keys $session '%1'
Select-ReplyChat $session 'fixture-beta'
Send-Keys $session '^e'
$null = Wait-Until { (Read-Control $session status).pending_archives -eq 0 -and -not (Test-ChatListed $session 'fixture-beta') } 'test chat archived' 60
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until { $state = Read-Control $session status; $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Beta' } 'test chat open in the archived list' 60
Save-Screen $session before-reply

Send-ReplyMessage $session 'Once reply from the archive' 'reply'
Invoke-PaletteCommand $session 'Show inbox chats'
$null = Wait-Until { -not (Read-Control $session status).show_archived } 'inbox shown after the reply'
Send-Keys $session '%1'
$null = Wait-Until { $state = Read-Control $session status; $state.current_view.inbox -and (Test-ChatListed $session 'fixture-beta') } 'replied chat back in Combined' 60
Save-Screen $session combined-inbox
$inMessenger = $false
foreach ($number in 2..4) {
    Send-Keys $session "%$number"
    Start-Sleep -Seconds 2
    if (Test-ChatListed $session 'fixture-beta') { $inMessenger = $true; Save-Screen $session whatsapp-inbox; break }
}
Assert-That $inMessenger 'replied chat is missing from its messenger inbox'
Send-Keys $session '%1'

$old = Get-App $session
$oldPid = $session.pid
$oldTicks = $session.startTicks
Invoke-PaletteCommand $session 'Quit Postbox'
$null = Wait-Until { $old.Refresh(); $old.HasExited } 'close for same-profile reply restart'
$start.Environment['WAZIG_VERIFY_RESTART'] = $session.id
$app = [Diagnostics.Process]::Start($start)
$session.pid = $app.Id
$session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
$session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'session.json')
@{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $session.pid; new_start = $session.startTicks; root = $session.root; id = $session.id; sha256 = $session.sha256 } |
    ConvertTo-Json | Set-Content (Join-Path $session.evidence 'restart.json')
$null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'restarted reply fixture window'
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
Send-Keys $session '%i'
$null = Wait-Until { $state = Read-Control $session status; $state.current_view.inbox -and (Test-ChatListed $session 'fixture-beta') } 'replied chat still in Combined after restart' 60
Save-Screen $session after-restart
Hub-Pass $session reply-returns

Select-ReplyChat $session 'fixture-beta'
Send-Keys $session '^+e'
$null = Wait-Until { -not (Test-ChatListed $session 'fixture-beta') } 'test chat kept archived' 60
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until { $state = Read-Control $session status; $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Beta' } 'kept chat open in the archived list' 60
Send-ReplyMessage $session 'Once reply to a kept chat' 'kept'
Invoke-PaletteCommand $session 'Refresh'
Start-Sleep -Seconds 5
Invoke-PaletteCommand $session 'Show inbox chats'
$null = Wait-Until { -not (Read-Control $session status).show_archived } 'inbox after the kept reply'
Assert-That (-not (Test-ChatListed $session 'fixture-beta')) 'a Keep archived chat came back after a reply'
Save-Screen $session kept-stays
Hub-Pass $session kept-stays-archived
