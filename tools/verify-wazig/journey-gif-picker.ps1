$gifChat = 'paste:whatsapp'
$gifKey = 'fixture-' + [guid]::NewGuid().ToString('N')
$gifPreferences = "HKCU:\Software\MessagesVerification\$($session.id)\Software\Messages"
$gifNoKeyNotice = 'GIF search needs a GIPHY key'
$gifSearchNotice = 'GIF search failed. Press Enter to retry'
$gifDownloadNotice = 'GIF download failed. Press Enter to retry'

function Get-GifPicker($Session) { (Read-Control $Session status).gif_picker }

function Wait-GifPicker($Session, [string]$Status, [int]$Count, [string]$Description) {
    return Wait-Until {
        $picker = Get-GifPicker $Session
        if ($picker -and $picker.status -ceq $Status -and $picker.count -eq $Count -and $picker.tiles -eq $Count -and -not $picker.downloading) { $picker }
    } $Description
}

function Wait-GifFailure($Session, [string]$Notice, [string]$Description) {
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.update_card.error -ceq $Notice -and $state.gif_picker -and -not $state.gif_picker.downloading
    } $Description
}

function Get-GiphyRows($Session) { @(Read-BridgeRequests $Session | Where-Object { $_.kind -ceq 'giphy' }) }

function Get-GifSends($Session) { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' }) }

Invoke-PaletteCommand $session 'Verification Paste whatsapp'
$null = Wait-Until { (Read-Control $session status).selected.id -ceq $gifChat } "gif-picker: $gifChat selected"
$null = Wait-Until { @((Read-Control $session messages).messages | Where-Object { $_.id -ceq 'GIF-ORIGINAL' }).Count -eq 1 } 'gif-picker: original message loaded'
Assert-That ($null -eq (Get-ItemProperty $gifPreferences -Name GiphyApiKey -ErrorAction SilentlyContinue)) 'gif-picker: a key existed before the journey stored one'

Invoke-PaletteCommand $session 'Send a GIF'
$null = Wait-Until { (Read-Control $session status).update_card.error -ceq $gifNoKeyNotice } 'gif-picker: missing key notice'
$noKey = Read-Control $session status
Assert-That ($null -eq $noKey.gif_picker) 'gif-picker: picker opened without a key'
Assert-That ((Get-GiphyRows $session).Count -eq 0) 'gif-picker: GIPHY was called without a key'
Save-Screen $session 'no-key'
Hub-Pass $session 'no-key-notice'

if (-not (Test-Path $gifPreferences)) { $null = New-Item -Path $gifPreferences -Force }
Set-ItemProperty -Path $gifPreferences -Name GiphyApiKey -Value $gifKey -Type String
$gifKeySha = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($gifKey))).Replace('-', '').ToLowerInvariant()

Invoke-PaletteCommand $session 'Compose message'
Send-Keys $session '{UP}'
$null = Wait-Until { @((Read-Control $session messages).messages | Where-Object { $_.selected }).Count -eq 1 } 'gif-picker: arrow up focuses the original'
Send-Keys $session '{ENTER}'
$null = Wait-Until { (Read-Control $session status).reply.id -ceq 'GIF-ORIGINAL' } 'gif-picker: reply started on the original'
Send-Keys $session 'gif draft'
$compose = Get-Edit (Get-Window $session) '1032'
$null = Wait-Until { (Read-Edit $compose) -ceq 'gif draft' } 'gif-picker: draft typed'

Invoke-PaletteCommand $session 'Send a GIF'
$trending = Wait-GifPicker $session 'ready' 3 'gif-picker: trending results with previews'
$open = Read-Control $session status
Assert-That ($open.reply.id -ceq 'GIF-ORIGINAL') 'gif-picker: opening changed the reply'
Assert-That ($null -eq $open.update_card.error -or $open.update_card.error -ceq '') 'gif-picker: notice left over after the key was stored'
Save-Screen $session 'trending'
Hub-Pass $session 'trending'

Send-Keys $session '{ESC}'
$null = Wait-Until { $null -eq (Get-GifPicker $session) } 'gif-picker: Escape closed the picker'
$closed = Read-Control $session status
Assert-That ($closed.staged_attachment_count -eq 0 -and $closed.pending_sends -eq 0) 'gif-picker: Escape staged or sent something'
Assert-That ($closed.reply.id -ceq 'GIF-ORIGINAL') 'gif-picker: Escape dropped the reply'
Assert-That ((Read-Edit $compose) -ceq 'gif draft') 'gif-picker: Escape lost the draft'
Assert-That ((Get-GifSends $session).Count -eq 0) 'gif-picker: Escape sent to the hub'
Save-Screen $session 'escaped'
Hub-Pass $session 'escape-keeps-draft'

Invoke-PaletteCommand $session 'Send a GIF'
$null = Wait-GifPicker $session 'ready' 3 'gif-picker: picker reopened'
Send-Keys $session 'boom'
Send-Keys $session '{ENTER}'
Wait-GifFailure $session $gifSearchNotice 'gif-picker: failed search notice'
$failedSearch = Get-GifPicker $session
Assert-That ($failedSearch.status -ceq 'failed') 'gif-picker: failed search left the picker in the wrong state'
Save-Screen $session 'search-failed'
Send-Keys $session '{ENTER}'
$boom = Wait-GifPicker $session 'ready' 2 'gif-picker: retry after a failed search'
Assert-That ($boom.query -ceq 'boom') 'gif-picker: retry lost the query'
Hub-Pass $session 'search-retry'

Send-Keys $session '{BACKSPACE 4}'
Send-Keys $session 'cats'
Send-Keys $session '{ENTER}'
$cats = Wait-Until {
    $picker = Get-GifPicker $session
    if ($picker -and $picker.status -ceq 'ready' -and $picker.query -ceq 'cats' -and $picker.count -eq 2 -and $picker.tiles -eq 2) { $picker }
} 'gif-picker: cats results with previews'
Save-Screen $session 'cats'
Send-Keys $session '{RIGHT}'
$null = Wait-Until { (Get-GifPicker $session).selected -eq 1 } 'gif-picker: arrow selects the second result'
Send-Keys $session '{ENTER}'
Wait-GifFailure $session $gifDownloadNotice 'gif-picker: failed download notice'
$failedDownload = Read-Control $session status
Assert-That ($failedDownload.gif_picker.status -ceq 'ready' -and $failedDownload.staged_attachment_count -eq 0) 'gif-picker: failed download staged or closed'
Save-Screen $session 'download-failed'
Send-Keys $session '{ENTER}'
$null = Wait-Until { $null -eq (Get-GifPicker $session) -and (Read-Control $session status).staged_attachment_count -eq 1 } 'gif-picker: retry staged the GIF and closed the picker'
$staged = Read-Control $session status
Assert-That ($staged.reply.id -ceq 'GIF-ORIGINAL' -and $staged.pending_sends -eq 0) 'gif-picker: staging changed the reply or sent early'
Assert-That ((Get-GifSends $session).Count -eq 0) 'gif-picker: sent before Enter'
Assert-That ((Read-Edit $compose) -ceq 'gif draft') 'gif-picker: staging lost the draft'
Save-Screen $session 'staged'
Hub-Pass $session 'staged'

Invoke-PaletteCommand $session 'Compose message'
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    @(Get-GifSends $session | Where-Object { $_.accepted }).Count -eq 1 -and (Read-Control $session status).pending_sends -eq 0
} 'gif-picker: GIF received exactly once'
$sends = @(Get-GifSends $session)
Assert-That ($sends.Count -eq 1) 'gif-picker: duplicate or failed send attempts'
$send = $sends[0]
Assert-That ($send.multipart -and $send.status -eq 200 -and $send.body.chat -ceq $gifChat -and $send.body.text -ceq 'gif draft' -and $send.body.reply_to -ceq 'GIF-ORIGINAL') 'gif-picker: send body wrong'
Assert-That ($send.body.file -like '*.gif' -and $send.body.client_id -match '^[A-Za-z0-9]+$') 'gif-picker: send file or id wrong'
$upload = Join-Path $session.evidence $send.upload
$bitmap = [Drawing.Bitmap]::new($upload)
try {
    $dimensions = @($bitmap.Width, $bitmap.Height)
    $left = $bitmap.GetPixel(0, 0)
    $right = $bitmap.GetPixel($bitmap.Width - 1, 0)
    $pixels = @($left.R, $left.G, $left.B, $right.R, $right.G, $right.B)
} finally { $bitmap.Dispose() }
Assert-That (($dimensions -join 'x') -ceq '64x48') 'gif-picker: uploaded GIF is not the original rendition'
Assert-That (($pixels -join ',') -ceq '32,180,220,250,250,250') 'gif-picker: uploaded GIF is not the picked result'
$shown = Wait-Until {
    $messages = Read-Control $session messages
    $row = @($messages.messages | Where-Object { $_.id -ceq $send.message_id -and $_.from_me -and $_.media_type -eq 'image' -and $_.quoted_msg_id -ceq 'GIF-ORIGINAL' })
    if ($row.Count -eq 1) { $messages }
} 'gif-picker: sent GIF visible as a reply'
$null = Wait-Until { (Read-Control $session status).reply.id -ceq '' } 'gif-picker: send cleared the reply'
$shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'sent.messages.json')
Save-Screen $session 'sent'
Hub-Pass $session 'sent-with-reply'

Invoke-PaletteCommand $session 'Verification Paste slack'
$null = Wait-Until { (Read-Control $session status).selected.id -ceq 'paste:slack' } 'gif-picker: second chat selected'
$other = Read-Control $session status
Assert-That ($other.staged_attachment_count -eq 0 -and $null -eq $other.gif_picker) 'gif-picker: GIF state leaked into another chat'
Hub-Pass $session 'chat-isolated'

$kind = (Get-Item $gifPreferences).GetValueKind('GiphyApiKey').ToString()
$stored = [byte[]](Get-ItemProperty $gifPreferences).GiphyApiKey
$storedHex = [BitConverter]::ToString($stored).Replace('-', '')
$plainUtf8 = [BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($gifKey)).Replace('-', '')
$plainUtf16 = [BitConverter]::ToString([Text.Encoding]::Unicode.GetBytes($gifKey)).Replace('-', '')
Assert-That ($kind -ceq 'Binary') 'gif-picker: key was not migrated to protected storage'
Assert-That (-not $storedHex.Contains($plainUtf8) -and -not $storedHex.Contains($plainUtf16)) 'gif-picker: key stored as plain text'

$rows = Get-GiphyRows $session
Assert-That ($rows.Count -gt 0 -and @($rows | Where-Object { $_.key_sha256 -and $_.key_sha256 -cne $gifKeySha }).Count -eq 0) 'gif-picker: GIPHY saw a different key than the stored one'
Assert-That (@($rows | Where-Object { $_.path -like '*api_key*' -or $_.wire_path -like '*api_key*' }).Count -eq 0) 'gif-picker: log carries the key'
$original = @($rows | Where-Object { $_.id -ceq 'catwave3' -and $_.rendition -ceq 'giphy' -and $_.status -eq 200 })
Assert-That ($original.Count -eq 1) 'gif-picker: the picked original was not served once'
$uploadSha = (Get-FileHash $upload -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-That ($original[0].file_sha256 -ceq $uploadSha -and $send.file_sha256 -ceq $uploadSha) 'gif-picker: uploaded bytes differ from the served original'

@{
    key_sha256 = $gifKeySha
    key_kind = $kind
    key_plain_in_registry = $false
    upload = $send.upload
    upload_sha256 = $uploadSha
    dimensions = $dimensions
    pixels = $pixels
    client_id = $send.body.client_id
    picked = 'catwave3'
    trending_count = $trending.count
    boom_count = $boom.count
    cats_count = $cats.count
} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $session.evidence 'gif-picker.json')

$leaks = @(Get-ChildItem $session.evidence -Recurse -File | Where-Object { $_.Name -ne 'run.log' -and $_.Extension -in @('.json', '.jsonl', '.txt', '.log') } | Where-Object { Select-String -Path $_.FullName -SimpleMatch $gifKey -Quiet })
Assert-That ($leaks.Count -eq 0) "gif-picker: key found in evidence: $($leaks.Name -join ', ')"
Hub-Pass $session 'key-protected'
Save-Screen $session after
