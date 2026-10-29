. "$PSScriptRoot/voice.ps1"
Assert-That (Test-Path $env:VOICE_LANGUAGE_RESULTS) 'Actual product formatter results missing'
$data = Get-Content $env:VOICE_LANGUAGE_RESULTS -Raw | ConvertFrom-Json
Assert-That ($data.version -ceq $session.expected_version) 'Formatter and displayed executable versions differ'
$media = Join-Path $messages 'hub-media'
$null = Wait-Until {
    $rows = @(Read-VoiceMessages $session | Where-Object media_type -eq 'audio')
    $rows.Count -eq 5 -and @(Get-ChildItem $media -Filter '*.ogg' -ErrorAction SilentlyContinue).Count -eq 5
} 'five isolated voice notes downloaded' -Seconds 90
$records = @()
foreach ($language in @('de', 'en')) {
    $row = @($data.cases | Where-Object id -CEQ "$language-short")
    Assert-That ($row.Count -eq 1) "Missing actual $language formatter result"
    $formatted = $row[0].formatted
    Send-Keys $session '^{TAB}'
    $null = Wait-Until { (Read-Control $session messages).chat.id -eq 'fixture-beta' } 'other chat open before cache update'
    Get-ChildItem $messages -Directory -Filter 'voice-format-*' | Remove-Item -Recurse -Force
    foreach ($file in @(Get-ChildItem $media -Filter '*.ogg')) {
        Set-Content -LiteralPath "$($file.FullName).txt" -Value $formatted -NoNewline -Encoding utf8NoBOM
    }
    Send-Keys $session '^+{TAB}'
    $null = Wait-Until {
        $shown = @(Read-VoiceMessages $session | Where-Object media_type -eq 'audio')
        $shown.Count -eq 5 -and @($shown | Where-Object transcript_chars -NE $formatted.Length).Count -eq 0
    } "actual $language formatted output loaded into every voice bubble"
    $layout = Get-VoiceLayout $session
    $handle = Get-VoiceCanvas $session
    $bounds = [VerifyVoice]::Bounds($session.pid, $handle)
    $target = @(Get-VoiceRows $layout | Where-Object { $_.bubble[3] -gt $_.bubble[1] }) | Select-Object -Last 1
    Assert-That ($null -ne $target) 'No visible voice bubble'
    if (-not $target.expanded -and $target.toggle[3] -gt $target.toggle[1]) {
        $x = $bounds.Left + [int](($target.toggle[0] + $target.toggle[2]) / 2)
        $y = $bounds.Top + [int](($target.toggle[1] + $target.toggle[3]) / 2)
        [VerifyMenus]::Click($session.pid, $x, $y, $false)
        $null = Wait-Until { @(Read-VoiceMessages $session | Where-Object { $_.id -eq $target.id -and $_.expanded }).Count -eq 1 } 'actual transcript expanded'
    }
    Save-Screen $session $language
    $shown = Read-Control $session messages
    $shown | ConvertTo-Json -Depth 15 | Set-Content (Join-Path $session.evidence "$language.messages.json")
    $records += @{ language = $language; case = $row[0].id; formatted = $formatted; chars = $formatted.Length; screenshot = "$language.png"; message = $target.id }
}
$records | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $session.evidence 'displayed-results.json')
