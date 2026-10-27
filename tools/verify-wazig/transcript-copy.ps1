Add-Type -Path "$PSScriptRoot/transcript-copy.cs"

function Invoke-TranscriptMark($Session, [string]$Id, [byte]$Modifier = 17) {
    $row = @(Read-VoiceMessages $Session | Where-Object id -CEQ $Id)[0]
    $canvas = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
    $origin = [VerifyWindow+Point]::new()
    $rect = [VerifyWindow+Rect]::new()
    Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$origin)) 'Cannot map transcript canvas'
    Assert-That ([VerifyWindow]::GetClientRect($canvas, [ref]$rect)) 'Cannot measure transcript canvas'
    Assert-That ($row.bubble[1] -ge 0 -and $row.bubble[3] -le $rect.Bottom -and $row.bubble[3] -gt $row.bubble[1]) "Transcript target not visible: $Id"
    $x = $origin.X + [int](($row.bubble[0] + $row.bubble[2]) / 2)
    $y = $origin.Y + [int](($row.bubble[1] + $row.bubble[3]) / 2)
    [VerifyTranscriptCopy]::Click($Session.pid, $x, $y, $Modifier)
    Add-Content (Join-Path $Session.evidence 'actions.log') "mark: $Id modifier=$Modifier"
}

function Invoke-TranscriptCopyJourney($Session, [string]$Messages) {
    $files = @(Get-ChildItem (Join-Path $Messages 'hub-media') -Filter '*.ogg' | Sort-Object Name)
    $expectedByFile = @{}
    foreach ($file in $files) {
        $text = "Raw words from $($file.BaseName): Grüße, café, punctuation!`nSecond line stays raw."
        Set-Content -LiteralPath "$($file.FullName).txt" -Value $text -NoNewline -Encoding utf8NoBOM
        $expectedByFile[$file.Name] = $text
    }
    Open-VoiceChatAgain $Session
    $null = Wait-Until { @(Read-VoiceMessages $Session | Where-Object { $_.media_type -eq 'audio' -and $_.transcript_chars -gt 0 -and $_.transcript_chars -lt 200 }).Count -eq 5 } 'short raw transcripts restored'
    Send-Keys $Session '%g'
    $null = Get-VoiceLayout $Session
    Invoke-TranscriptMark $Session 'VOICE-5'
    Invoke-TranscriptMark $Session 'VOICE-3'
    Invoke-TranscriptMark $Session 'VOICE-4'
    Save-Screen $Session 'transcripts-marked'
    Send-Keys $Session '^k'
    $palette = Get-PaletteWindow $Session
    $edit = Get-Edit $palette '1064'
    $list = Get-Edit $palette '1072'
    Send-Keys $Session 'Copy all transcripts'
    $null = Wait-Until { (Read-Edit $edit) -ceq 'Copy all transcripts' } 'copy transcripts query'
    $labels = @(Read-ListLabels $list)
    $labels | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'transcript-palette.json')
    Assert-That ($labels.Count -eq 1 -and $labels[0] -ceq 'Copy all transcripts') 'Copy all transcripts command missing for three marked voice notes'
    Save-Screen $Session 'transcripts-palette'
    [Windows.Forms.Clipboard]::SetText('clipboard negative control')
    Send-Keys $Session '{ENTER}'
    $actual = [Windows.Forms.Clipboard]::GetText()
    $rows = @(Read-VoiceMessages $Session | Where-Object { $_.id -in @('VOICE-3', 'VOICE-4', 'VOICE-5') } | Sort-Object time)
    $expected = @($rows | ForEach-Object {
        $row = $_
        $file = @($files | Where-Object { $_.Name -ceq [IO.Path]::GetFileName($row.local_path) })
        if ($file.Count -ne 1) { throw "Cannot map raw voice file: $($row.id)" }
        $expectedByFile[$file[0].Name]
    }) -join "`r`n`r`n"
    @{ ids = @($rows.id); expected = $expected; actual = $actual; labels = $labels } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session.evidence 'transcript-copy.json')
    Assert-That ($actual -ceq $expected) 'Copied transcripts differ from raw text or chronological order'
    Save-Screen $Session 'transcripts-copied'
    Send-Keys $Session '{ESC}'
    Send-Keys $Session '^k'
    $palette = Get-PaletteWindow $Session
    Send-Keys $Session 'Copy all transcripts'
    $list = Get-Edit $palette '1072'
    Assert-That ((Read-ListCount $list) -eq 0) 'Escape did not clear transcript marks'
    Send-Keys $Session '{ESC}'
}
