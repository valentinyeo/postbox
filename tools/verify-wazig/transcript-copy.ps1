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
    Invoke-TranscriptMark $Session 'VOICE-TEXT'
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
    $rawRows = @($rows | ForEach-Object {
        $row = $_
        $file = @($files | Where-Object { $_.Name -ceq [IO.Path]::GetFileName($row.local_path) })
        if ($file.Count -ne 1) { throw "Cannot map raw voice file: $($row.id)" }
        @{ id = $row.id; time = $row.time; raw = $expectedByFile[$file[0].Name] }
    })
    $expected = @($rawRows.raw) -join "`r`n`r`n"
    @{ ids = @($rows.id); raw_rows = $rawRows; marked = @(Read-VoiceMessages $Session | Where-Object marked | ForEach-Object id); expected = $expected; actual = $actual; labels = $labels; title = (Get-Window $Session).Current.Name } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session.evidence 'transcript-copy.json')
    Assert-That ($actual -ceq $expected) 'Copied transcripts differ from raw text or chronological order'
    Save-Screen $Session 'transcripts-copied'
    $paste = [Diagnostics.ProcessStartInfo]::new('pwsh')
    $paste.UseShellExecute = $false
    foreach ($argument in @('-NoProfile', '-STA', '-File', (Join-Path $PSScriptRoot 'paste-transcripts.ps1'), '-Evidence', $Session.evidence)) { $paste.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::Start($paste)
    try {
        Assert-That ($child.WaitForExit(20000)) 'Separate paste app timed out'
        Assert-That ($child.ExitCode -eq 0) 'Separate paste app failed'
    } finally {
        if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
        $child.Dispose()
    }
    $pasted = [IO.File]::ReadAllText((Join-Path $Session.evidence 'transcripts-pasted.txt'))
    Assert-That ($pasted.Replace("`r`n", "`n") -ceq $expected.Replace("`r`n", "`n")) 'Separate app pasted different transcript words'
    $missingRow = @($rows | Where-Object id -CEQ 'VOICE-4')[0]
    Remove-Item -LiteralPath "$($missingRow.local_path).txt"
    Invoke-PaletteCommand $Session 'Copy all transcripts'
    $partial = [Windows.Forms.Clipboard]::GetText()
    $partialExpected = @($rawRows | Where-Object id -CNE 'VOICE-4' | ForEach-Object raw) -join "`r`n`r`n"
    $missingTime = ([DateTimeOffset]::Parse($missingRow.time)).ToLocalTime().ToString('HH:mm')
    $title = (Get-Window $Session).Current.Name
    @{ actual = $partial; expected = $partialExpected; missing_id = $missingRow.id; missing_time = $missingTime; title = $title } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session.evidence 'transcript-missing.json')
    Assert-That ($partial -ceq $partialExpected -and $title.Contains("Copied 2 transcripts. Missing: $missingTime")) 'Missing transcript was silently omitted or copied from its formatted display'
    Save-Screen $Session 'transcripts-missing'
    Send-Keys $Session '{ESC}'
    Send-Keys $Session '^k'
    $palette = Get-PaletteWindow $Session
    Send-Keys $Session 'Copy all transcripts'
    $list = Get-Edit $palette '1072'
    $null = Wait-Until { (Read-ListCount $list) -eq 0 } 'Escape clears transcript marks'
    Assert-That (@(Read-VoiceMessages $Session | Where-Object marked).Count -eq 0) 'Escape left marked messages'
    Send-Keys $Session '{ESC}'
    Invoke-TranscriptMark $Session 'VOICE-3'
    Invoke-TranscriptMark $Session 'VOICE-5' 16
    $ranged = @(Read-VoiceMessages $Session | Where-Object marked | ForEach-Object id)
    Assert-That (($ranged -join ',') -ceq 'VOICE-3,VOICE-TEXT,VOICE-4,VOICE-5') 'Shift-click did not mark the message range'
    Open-VoiceChatAgain $Session
    Assert-That (@(Read-VoiceMessages $Session | Where-Object marked).Count -eq 0) 'Marks leaked across a chat switch'
    @{ range = $ranged; escape_cleared = $true; chat_switch_cleared = $true; pasted = $pasted } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session.evidence 'transcript-selection.json')
}
