$private = Join-Path $messages 'unified-journal-v2'
$offlineDir = Join-Path $session.root 'offline'
$copy = Join-Path $offlineDir 'Messages.exe'
$probeScript = Join-Path $offlineDir 'probe.ps1'
$probeResult = Join-Path $offlineDir 'probe.json'
$probeRelease = Join-Path $offlineDir 'release'
$control = Join-Path $cache 'rollback-aged-control.msg'
$userName = 'pb' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
$ruleName = 'postbox-rollback-' + [Guid]::NewGuid().ToString('N')
$user = $null
$rule = $null
$probe = $null
$offline = $null
$profileRemoved = $false
$userRemoved = $false
$ruleRemoved = $false
$privateBefore = $null
$privateAfter = $null
$proof = $null
$offlineCleanupUnsafe = $false

Assert-That ($env:GITHUB_ACTIONS -ceq 'true' -and $env:RUNNER_TEMP -and $session.root.StartsWith(([IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) 'Offline cleanup requires owned Actions root'
Assert-That (-not (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) 'Disposable user already exists'
Assert-That (-not (Test-Path (Join-Path (Join-Path $env:SystemDrive 'Users') $userName)) -and @((Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -and [IO.Path]::GetFileName($_.LocalPath).StartsWith($userName, [StringComparison]::OrdinalIgnoreCase) })).Count -eq 0) 'Disposable profile already exists'
Assert-That (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) 'Disposable firewall rule already exists'
Assert-That (-not (Test-Path $offlineDir) -and -not (Test-Path $control)) 'Offline cleanup paths already exist'
Assert-That (-not (Test-Path (Join-Path $local 'Programs\wacli\wacli.exe'))) 'Offline provider executable already exists'
Assert-That (-not (Get-Process -Id $session.pid -ErrorAction SilentlyContinue)) 'Prior app still running'
$firewallProfiles = @(Get-NetFirewallProfile)
Assert-That ((Get-Service MpsSvc).Status -eq 'Running' -and $firewallProfiles.Count -eq 3 -and @($firewallProfiles | Where-Object Enabled -NE 'True').Count -eq 0) 'Windows firewall unavailable'

try {
    New-Item $offlineDir -ItemType Directory -ErrorAction Stop | Out-Null
    Copy-Item (Join-Path $session.evidence 'historical-847/old-bin/bin/*') $offlineDir
    Assert-That ((Get-FileHash $copy).Hash -ceq $oldHash) 'Offline executable differs from historical build'
    $password = [Security.SecureString]::new()
    $random = [byte[]]::new(40)
    [Security.Cryptography.RandomNumberGenerator]::Fill($random)
    foreach ($byte in $random) { $password.AppendChar('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%'[[int]$byte % 66]) }
    [Array]::Clear($random, 0, $random.Length)
    $password.MakeReadOnly()
    $user = New-LocalUser -Name $userName -Password $password -PasswordNeverExpires -UserMayNotChangePassword -ErrorAction Stop
    $sid = $user.SID.Value
    Assert-That ($sid -cne $runnerSid -and -not (Get-CimInstance Win32_UserProfile | Where-Object SID -CEQ $sid)) 'Disposable identity is not fresh'
    $acl = Get-Acl -LiteralPath $session.root
    $access = [Security.AccessControl.FileSystemAccessRule]::new($user.SID, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($access)
    Set-Acl -LiteralPath $session.root -AclObject $acl
    $rule = New-NetFirewallRule -Name $ruleName -DisplayName $ruleName -Direction Outbound -Action Block -Enabled True -Profile Any -Program $copy -ErrorAction Stop
    $activeRule = Get-NetFirewallRule -Name $ruleName -PolicyStore ActiveStore -ErrorAction Stop
    $filter = $activeRule | Get-NetFirewallApplicationFilter
    Assert-That ($activeRule.Enabled -eq 'True' -and $activeRule.Direction -eq 'Outbound' -and $activeRule.Action -eq 'Block' -and $filter.Program -ceq $copy) 'Offline firewall rule not active'

    @'
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if (Test-Path 'HKCU:\Software\Messages') { throw 'Disposable app registry is not fresh' }
if (Get-ChildItem Env: | Where-Object { $_.Name -match '^(WAZIG|WA_BRIDGE|GITHUB|GH_|DEEPGRAM|OPENROUTER|AZURE|AWS)' }) { throw 'Unexpected service credentials' }
$private = Join-Path $env:LOCALAPPDATA 'Messages\unified-journal-v2'
$files = @(Get-ChildItem $private -Recurse -File)
if (-not $files.Count) { throw 'No private files to probe' }
$folders = @($files | ForEach-Object DirectoryName | Sort-Object -Unique)
foreach ($file in $files) {
    $stream = [IO.File]::Open($file.FullName, 'Open', 'ReadWrite', 'ReadWrite')
    try { if ($stream.Length -gt 0) { $null = $stream.ReadByte() } } finally { $stream.Dispose() }
}
foreach ($folder in $folders) {
    $path = Join-Path $folder ('acl-probe-' + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($path, 'read-write-delete')
    if ([IO.File]::ReadAllText($path) -cne 'read-write-delete') { throw 'Private probe read failed' }
    [IO.File]::Delete($path)
    if (Test-Path $path) { throw 'Private probe delete failed' }
}
@{ sid = $sid; files_opened_readwrite = $files.Count; directories_read_write_delete = $folders.Count; registry_absent = $true } | ConvertTo-Json | Set-Content $env:PROBE_RESULT
$deadline = [DateTime]::UtcNow.AddSeconds(60)
while (-not (Test-Path $env:PROBE_RELEASE)) {
    if ([DateTime]::UtcNow -gt $deadline) { throw 'Probe release timed out' }
    Start-Sleep -Milliseconds 100
}
'@ | Set-Content -LiteralPath $probeScript -Encoding utf8
    $base = [Diagnostics.ProcessStartInfo]::new()
    $base.UseShellExecute = $false
    $base.UserName = $userName
    $base.Domain = $env:COMPUTERNAME
    $base.Password = $password
    $base.LoadUserProfile = $true
    $base.Environment.Clear()
    foreach ($name in @('SystemRoot', 'WINDIR', 'COMSPEC')) { $base.Environment[$name] = [Environment]::GetEnvironmentVariable($name) }
    $base.Environment['PATH'] = Join-Path $env:SystemRoot 'System32'
    $base.Environment['LOCALAPPDATA'] = $local
    $base.Environment['APPDATA'] = $local
    $base.Environment['USERPROFILE'] = $profile
    $base.Environment['USERNAME'] = $userName
    $base.Environment['USERDOMAIN'] = $env:COMPUTERNAME
    $base.Environment['TEMP'] = $offlineDir
    $base.Environment['TMP'] = $offlineDir
    $base.Environment['PROBE_RESULT'] = $probeResult
    $base.Environment['PROBE_RELEASE'] = $probeRelease
    $base.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($arg in @('-NoProfile', '-NonInteractive', '-File', $probeScript)) { $base.ArgumentList.Add($arg) }
    $probe = [Diagnostics.Process]::Start($base)
    $probeTicks = $probe.StartTime.ToUniversalTime().Ticks.ToString()
    $null = Wait-Until { $probe.Refresh(); if ($probe.HasExited) { throw "Disposable ACL probe exited: $($probe.ExitCode)" }; Test-Path $probeResult } 'disposable ACL probe' -Seconds 60
    Assert-That ((Process-Sid $probe.Id) -ceq $sid) 'ACL probe ran as another user'
    $createdProfiles = @(Get-CimInstance Win32_UserProfile | Where-Object SID -CEQ $sid)
    Assert-That ($createdProfiles.Count -eq 1 -and $createdProfiles[0].Loaded -and [IO.Path]::GetFileName($createdProfiles[0].LocalPath).StartsWith($userName, [StringComparison]::OrdinalIgnoreCase) -and $createdProfiles[0].LocalPath.StartsWith(($env:SystemDrive + '\Users\'), [StringComparison]::OrdinalIgnoreCase)) 'Disposable profile identity differs'
    $createdProfilePath = $createdProfiles[0].LocalPath
    $aclProof = Get-Content $probeResult -Raw | ConvertFrom-Json
    Assert-That ($aclProof.sid -ceq $sid -and $aclProof.registry_absent -and $aclProof.files_opened_readwrite -gt 0 -and $aclProof.directories_read_write_delete -gt 0) 'Private ACL probe failed'
    $aclProof | Add-Member -NotePropertyName pid -NotePropertyValue $probe.Id
    $aclProof | Add-Member -NotePropertyName start_ticks -NotePropertyValue $probeTicks
    $aclProof | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'offline-acl.json')
    Set-Content $probeRelease 'release'
    Assert-That ($probe.WaitForExit(10000) -and $probe.ExitCode -eq 0) 'Disposable ACL probe did not finish'

    [IO.File]::WriteAllText($control, 'historical cleanup positive control')
    (Get-Item $control).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-30)
    $controlItem = Get-Item $control
    Assert-That ($controlItem.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-14)) 'Cleanup control is not old enough'
    $controlWritten = $controlItem.LastWriteTimeUtc.ToString('o')
    Copy-Item $control (Join-Path $session.evidence 'offline-aged-control.before')
    $privateBefore = Get-RollbackFiles $private
    Copy-Item (Join-Path $messages 'launch-log.txt') (Join-Path $session.evidence 'offline-before.launch.log')
    $launchBefore = Get-Content (Join-Path $session.evidence 'offline-before.launch.log') -Raw
    Copy-Item $private (Join-Path $session.evidence 'offline-private-before') -Recurse
    ConvertTo-Json -InputObject $privateBefore -Depth 8 | Set-Content (Join-Path $session.evidence 'offline-private-before.json')
    $base.FileName = $copy
    $base.ArgumentList.Clear()
    $null = $base.Environment.Remove('PROBE_RESULT')
    $null = $base.Environment.Remove('PROBE_RELEASE')
    Assert-That ($base.ArgumentList.Count -eq 0 -and $base.Environment['LOCALAPPDATA'] -ceq $local -and -not $base.Environment.ContainsKey('WAZIG_HUB_URL')) 'Offline app environment invalid'
    $offline = [Diagnostics.Process]::Start($base)
    $offlineTicks = $offline.StartTime.ToUniversalTime().Ticks.ToString()
    Assert-That ((Process-Sid $offline.Id) -ceq $sid -and $offline.Path -ceq $copy -and (Get-FileHash $offline.Path).Hash -ceq $oldHash) 'Offline process identity differs'
    $null = Wait-Until { $offline.Refresh(); if ($offline.HasExited) { throw "Offline historical app exited: $($offline.ExitCode)" }; -not (Test-Path $control) } 'historical aged cache deleted' -Seconds 60
    Assert-That ((Process-Sid $offline.Id) -ceq $sid) 'Offline process owner changed'
    $proof = @{ username = $userName; sid = $sid; user_profile_path = $createdProfilePath; runner_sid = $runnerSid; pid = $offline.Id; start_ticks = $offlineTicks; exe = $copy; sha256 = $oldHash; root = $session.root; local = $local; profile = $profile; fixture = $false; hub_disabled = $true; firewall_rule = $ruleName; firewall_program = $filter.Program; firewall_direction = 'Outbound'; firewall_action = 'Block'; firewall_profiles_enabled = $true; control_path = $control; control_written_utc = $controlWritten; observed_utc = [DateTime]::UtcNow.ToString('o'); control_deleted = $true; probe_pid = $probe.Id; probe_start_ticks = $probeTicks }
    Assert-That ($offline.StartTime.ToUniversalTime().Ticks.ToString() -ceq $offlineTicks -and $offline.Path -ceq $copy -and (Get-FileHash $offline.Path).Hash -ceq $oldHash -and (Process-Sid $offline.Id) -ceq $sid) 'Offline PID reused'
    $offline.Kill(); Assert-That ($offline.WaitForExit(10000)) 'Offline app did not stop'
    Copy-Item (Join-Path $messages 'launch-log.txt') (Join-Path $session.evidence 'offline-after.launch.log')
    $launchAfter = Get-Content (Join-Path $session.evidence 'offline-after.launch.log') -Raw
    Assert-That ($launchAfter.StartsWith($launchBefore) -and $launchAfter.Substring($launchBefore.Length).Contains('whatsapp backend: unavailable (URL not configured)')) 'Offline backend was not disabled'
    $privateAfter = Get-RollbackFiles $private
    Copy-Item $private (Join-Path $session.evidence 'offline-private-after') -Recurse
    ConvertTo-Json -InputObject $privateAfter -Depth 8 | Set-Content (Join-Path $session.evidence 'offline-private-after.json')
    Assert-That (($privateBefore | ConvertTo-Json -Depth 8 -Compress) -ceq ($privateAfter | ConvertTo-Json -Depth 8 -Compress)) 'Offline cleanup changed private files'
} finally {
    $cleanupErrors = @()
    $processesStopped = $true
    foreach ($process in @($offline, $probe)) {
        if ($null -eq $process) { continue }
        try {
            $process.Refresh()
            if (-not $process.HasExited) {
                $expectedTicks = if ($process -eq $offline) { $offlineTicks } else { $probeTicks }
                $expectedExe = if ($process -eq $offline) { $copy } else { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
                Assert-That ($process.StartTime.ToUniversalTime().Ticks.ToString() -ceq $expectedTicks -and $process.Path -ceq $expectedExe -and (Process-Sid $process.Id) -ceq $sid) 'Disposable process PID reused'
                $process.Kill(); Assert-That ($process.WaitForExit(10000)) 'Disposable process survived cleanup'
            }
        } catch { $processesStopped = $false; $offlineCleanupUnsafe = $true; $cleanupErrors += 'process cleanup failed' }
    }
    if ($null -ne $user -and $processesStopped) {
        try {
            $null = Wait-Until { @((Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -ceq $sid -and $_.Loaded })).Count -eq 0 } 'disposable profile unloaded' -Seconds 60
            $profiles = @(Get-CimInstance Win32_UserProfile | Where-Object SID -CEQ $sid)
            Assert-That ($profiles.Count -le 1) 'Unexpected disposable profiles'
            foreach ($entry in $profiles) {
                Assert-That (-not $entry.Loaded -and $entry.LocalPath.StartsWith(($env:SystemDrive + '\Users\'), [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($entry.LocalPath).StartsWith($userName, [StringComparison]::OrdinalIgnoreCase)) 'Disposable profile is still loaded or unexpected'
                $entry | Remove-CimInstance -ErrorAction Stop
            }
            $profileRemoved = @((Get-CimInstance Win32_UserProfile | Where-Object SID -CEQ $sid)).Count -eq 0 -and -not (Test-Path "Registry::HKEY_USERS\$sid") -and (-not $createdProfilePath -or -not (Test-Path -LiteralPath $createdProfilePath))
        } catch { $cleanupErrors += 'profile cleanup failed' }
        try {
            $existing = Get-LocalUser -Name $userName -ErrorAction Stop
            Assert-That ($existing.SID.Value -ceq $sid) 'Disposable user identity changed'
            Remove-LocalUser -SID $user.SID -ErrorAction Stop
            $userRemoved = $null -eq (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)
        } catch { $cleanupErrors += 'user cleanup failed' }
    }
    if ($null -ne $rule -and $processesStopped) {
        try {
            $existingRule = Get-NetFirewallRule -Name $ruleName -ErrorAction Stop
            Assert-That (($existingRule | Get-NetFirewallApplicationFilter).Program -ceq $copy) 'Disposable firewall identity changed'
            $existingRule | Remove-NetFirewallRule -ErrorAction Stop
            $ruleRemoved = $null -eq (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)
        } catch { $cleanupErrors += 'firewall cleanup failed' }
    }
    if ($null -ne $password) { $password.Dispose() }
    if ($cleanupErrors.Count -or ($null -ne $proof -and -not ($profileRemoved -and $userRemoved -and $ruleRemoved))) { throw ('Disposable cleanup incomplete: ' + ($cleanupErrors -join ', ')) }
}
Assert-That (-not (Test-Path 'HKCU:\Software\Messages')) 'Runner production preferences appeared during offline cleanup'
$proof.profile_removed = $profileRemoved
$proof.user_removed = $userRemoved
$proof.firewall_removed = $ruleRemoved
$proof | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $session.evidence 'offline-cleanup.json')
Hub-Pass $session old-offline-cache-cleanup
