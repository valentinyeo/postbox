. "$PSScriptRoot/menus.ps1"

function Select-OnceChat($Session, [string]$Id, [string]$Provider) {
    $null = Wait-Until { try { (Read-Control $Session chats).chats | Where-Object { $_.id -ceq $Id } } catch { $false } } "$Id listed" 60
    $null = Read-Control $Session select -Arguments @($Id, '--provider', $Provider)
    $null = Wait-Until { (Read-Control $Session status).selected.id -ceq $Id } "$Id selected" 30
}

function Send-OnceMessage($Session, [string]$Text, [string]$Label) {
    $before = @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.status -eq 200 }).Count
    Click-Control $Session '1032'
    Send-Keys $Session $Text
    Send-Keys $Session '{ENTER}'
    Start-Sleep -Milliseconds 800
    Invoke-PaletteCommand $Session 'Refresh'
    $null = Wait-Until {
        @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.status -eq 200 }).Count -eq $before + 1
    } "$Label send accepted by the hub" 30
    Start-Sleep -Seconds 10
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Label.messages.json")
    Save-Screen $Session $Label
    $rows = @((Read-Control $Session messages).messages | Where-Object { $_.text -like "$Text*" })
    $waiting = @((Read-Control $Session messages).messages | Where-Object { $_.text -like '*(sending)*' })
    $status = Read-Control $Session status
    @{ label = $Label; text = $Text; copies = $rows.Count; waiting = $waiting.Count; pending_sends = $status.pending_sends } |
        ConvertTo-Json | Set-Content (Join-Path $Session.evidence "$Label.once.json")
    Assert-That ($rows.Count -eq 1) "$Label sent message shows $($rows.Count) times, expected once"
    Assert-That ($waiting.Count -eq 0) "$Label still shows a (sending) bubble"
    Assert-That ($status.pending_sends -eq 0) "$Label outbox still holds the send"
}

Send-Keys $session '%1'
Select-OnceChat $session 'fixture-beta' 'whatsapp'
Send-OnceMessage $session 'Once normal chat message' 'normal-chat'

Send-Keys $session '^e'
$null = Wait-Until { (Read-Control $session status).pending_archives -eq 0 -and -not ((Read-Control $session chats).chats.id -contains 'fixture-beta') } 'test chat archived' 60
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until { $state = Read-Control $session status; $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Beta' } 'test chat open in the archived list' 60
Send-OnceMessage $session 'Once archived chat message' 'archived-chat'
Hub-Pass $session send-once-normal-and-archived
