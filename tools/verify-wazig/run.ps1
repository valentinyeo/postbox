param(
    [string]$Feature = 'search',
    [string]$Bin = 'zig-out/bin',
    [string]$Evidence = 'verification-evidence',
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
    [string]$ExpectedVersion = '0.0.526'
)
. "$PSScriptRoot/harness.ps1"
$registry = Get-Content (Join-Path $PSScriptRoot 'journeys.json') -Raw | ConvertFrom-Json
$journey = @($registry.journeys | Where-Object name -CEQ $Feature)
Assert-That ($journey.Count -eq 1) "Unknown verification journey: $Feature"
$journey = $journey[0]
if ($journey.library) { . (Join-Path $PSScriptRoot $journey.library) }
Assert-That ($env:GITHUB_ACTIONS -eq 'true') 'Verification runs only on GitHub Actions'
New-Item $Evidence -ItemType Directory -Force | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
@{ feature = $Feature; status = 'failed' } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'result.json')
Start-Transcript (Join-Path $Evidence 'run.log') | Out-Null
Assert-That (-not (Test-Path 'HKCU:\Software\Messages')) 'Hosted runner already has production app preferences'
$id = [Guid]::NewGuid().ToString()
$root = Join-Path $env:RUNNER_TEMP "wazig-verify-$id"
$local = Join-Path $root 'local'
$profile = Join-Path $root 'profile'
$messages = Join-Path $local 'Messages'
New-Item $messages, $profile -ItemType Directory -Force | Out-Null
foreach ($folder in @('Desktop', 'Documents', 'Pictures')) {
    New-Item (Join-Path $profile $folder) -ItemType Directory -Force | Out-Null
}
$tag = '0000000000000526'
if (-not $journey.hub) {
    Set-Content (Join-Path $messages 'account-tag.txt') $tag -NoNewline
    @{ data = @(
        @{ jid = 'verify-alpha'; name = 'Verification Alpha'; kind = 'direct'; last_message_ts = '' },
        @{ jid = 'verify-beta'; name = 'Verification Beta'; kind = 'direct'; last_message_ts = '' }
    ) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $messages "chats-$tag.json")
}
$exe = (Resolve-Path (Join-Path $Bin 'Messages.exe')).Path
foreach ($case in @('not-actions', 'not-isolated')) {
    $rejected = [Diagnostics.ProcessStartInfo]::new($exe)
    $rejected.UseShellExecute = $false
    $rejected.ArgumentList.Add('--verify-fixture')
    if ($case -eq 'not-actions') { $rejected.Environment['GITHUB_ACTIONS'] = 'false' }
    $null = $rejected.Environment.Remove('WAZIG_VERIFY_ROOT')
    $child = [Diagnostics.Process]::Start($rejected)
    try {
        Assert-That ($child.WaitForExit(10000)) "Unsafe fixture launch did not reject: $case"
        Assert-That ($child.ExitCode -ne 0) "Unsafe fixture launch succeeded: $case"
    } finally {
        if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
    }
    Add-Content (Join-Path $Evidence 'launch-guards.log') "REJECTED: $case"
}
$ctl = (Resolve-Path (Join-Path $Bin 'wazigctl.exe')).Path
$start = [Diagnostics.ProcessStartInfo]::new($exe)
$start.UseShellExecute = $false
$start.RedirectStandardError = $true
$start.ArgumentList.Add('--verify-fixture')
foreach ($argument in $journey.arguments) { $start.ArgumentList.Add($argument) }
$start.Environment['WAZIG_VERIFY_ROOT'] = $root
$start.Environment['WAZIG_VERIFY_ID'] = $id
$start.Environment['LOCALAPPDATA'] = $local
$start.Environment['APPDATA'] = $local
$start.Environment['USERPROFILE'] = $profile
$start.Environment['USERNAME'] = "verify-$id"
foreach ($name in @('DEEPGRAM_API_KEY', 'OPENROUTER_API_KEY', 'OPENROUTER_MODEL', 'WAZIG_FAKE_VERSION', 'WA_BRIDGE_KEY', 'WAZIG_VERIFY_HUB_URL', 'WAZIG_VERIFY_HUB_KEY', 'WAZIG_HUB_URL', 'WAZIG_HUB_TOKEN', 'WAZIG_VERIFY_RESTART')) { $null = $start.Environment.Remove($name) }
$bridge = $null
if ($journey.prepare) { . (Join-Path $PSScriptRoot $journey.prepare) }
if ($journey.hub) {
    $bridge = Start-FakeBridge $Evidence $root -Mode $journey.hub
    if ($journey.hub -eq 'legacy') {
        $start.Environment['WAZIG_VERIFY_HUB_URL'] = $bridge.url
        $start.Environment['WAZIG_VERIFY_HUB_KEY'] = 'fixture-key-not-a-secret'
    } else {
        $start.Environment['WAZIG_HUB_URL'] = $bridge.url
        $start.Environment['WAZIG_HUB_TOKEN'] = (Get-Content (Join-Path $PSScriptRoot 'fake-wa-bridge.py') | Where-Object { $_.StartsWith('KEY = ') }).Split("'")[1]
    }
}
try {
    $app = [Diagnostics.Process]::Start($start)
} catch {
    if ($null -ne $bridge) { $bridge.process.Kill(); $bridge.process.WaitForExit() }
    throw
}
$session = [ordered]@{
    id = $id; pid = $app.Id; startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    root = $root; evidence = $Evidence; exe = $exe; ctl = $ctl; username = "verify-$id"
    sha256 = (Get-FileHash $exe).Hash; commit = $env:GITHUB_SHA; feature = $Feature; expected_version = $ExpectedVersion
}
if ($null -ne $bridge) {
    $session['bridge_pid'] = $bridge.process.Id
    $session['bridge_start_ticks'] = $bridge.process.StartTime.ToUniversalTime().Ticks.ToString()
    $session['bridge_exe'] = (Get-Process -Id $bridge.process.Id).Path
    $session['bridge_url'] = $bridge.url
}
$session | ConvertTo-Json | Set-Content (Join-Path $Evidence 'session.json')
$session = Read-Session $Evidence
try {
    $null = Wait-Until { $app.Refresh(); if ($app.HasExited) { throw "App exited: $($app.ExitCode)" }; $app.MainWindowHandle -ne [IntPtr]::Zero } 'main window'
    if ($journey.maximize) { [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null }
    if ($null -ne $journey.chats) {
        $null = Wait-Until { (Read-Control $session status).chat_count -eq $journey.chats } 'hub chat list'
    }
    if ($journey.ready) { . (Join-Path $PSScriptRoot $journey.ready) }
    Invoke-Doctor $session
    $window = Get-Window $session
    $compose = Get-Edit $window '1032'
    Save-Screen $session before
    . (Join-Path $PSScriptRoot $journey.script)
    $final = Read-Control $session status
    Assert-That ($final.pending_sends -eq 0 -and $final.pending_archives -eq 0 -and $final.sync -eq 'stopped') 'Unexpected transport side effect'
    Assert-That (-not (Test-Path (Join-Path $profile '.wacli'))) 'Provider store was created'
    Assert-That (-not (Test-Path (Join-Path $messages 'telegram'))) 'Telegram store was created'
    if ($journey.provider) {
        Assert-That ((Get-Content $provider -Raw | ConvertFrom-Json).data.Count -eq 2) 'Fixture provider chat storage changed'
    } elseif (-not $journey.hub) {
        Assert-That ((Get-Content (Join-Path $messages "chats-$tag.json") -Raw | ConvertFrom-Json).data.Count -eq 2) 'Fixture chat storage changed'
    }
    $final | Add-Member -NotePropertyName production_preferences_absent -NotePropertyValue (-not (Test-Path 'HKCU:\Software\Messages'))
    $final | Add-Member -NotePropertyName whatsapp_store_absent -NotePropertyValue (-not (Test-Path (Join-Path $profile '.wacli')))
    $final | Add-Member -NotePropertyName telegram_store_absent -NotePropertyValue (-not (Test-Path (Join-Path $messages 'telegram')))
    Assert-That $final.production_preferences_absent 'Production app preferences were touched'
    $final | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'side-effects.json')
    "JOURNEY PASSED: $Feature" | Set-Content (Join-Path $Evidence 'result.txt')
} catch {
    "${Feature}: $($_.Exception.Message)" | Set-Content (Join-Path $Evidence 'failure.txt')
    try { Save-Screen $session failure } catch { $_ | Out-String | Add-Content (Join-Path $Evidence 'failure.txt') }
    throw
} finally {
    & "$PSScriptRoot/cleanup.ps1" -Evidence $Evidence
    $app.StandardError.ReadToEnd() | Set-Content (Join-Path $Evidence 'app.stderr.log')
    Stop-Transcript | Out-Null
}
$result = @{ feature = $Feature; status = 'passed' }
if ($journey.result_checks) {
    $result.checks = Get-Content (Join-Path $Evidence $journey.result_checks) -Raw | ConvertFrom-Json -AsHashtable
}
$result | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'result.json')
