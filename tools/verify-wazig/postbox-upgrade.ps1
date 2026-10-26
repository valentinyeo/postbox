param(
    [Parameter(Mandatory)][string]$Msi,
    [Parameter(Mandatory)][string]$Payload,
    [Parameter(Mandatory)][string]$CacheId,
    [string]$Version = '0.9.999',
    [string]$Evidence = 'postbox-evidence',
    [switch]$RedControl
)
. "$PSScriptRoot/harness.ps1"
Assert-That ($env:GITHUB_ACTIONS -eq 'true') 'Upgrade journey only runs on GitHub Actions'
Assert-That (-not (Test-Path 'HKCU:\Software\Messages')) 'Hosted runner has existing product preferences'
$Msi = (Resolve-Path $Msi).Path
$Payload = (Resolve-Path $Payload).Path
New-Item $Evidence -ItemType Directory -Force | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
$id = [Guid]::NewGuid().ToString()
$root = Join-Path $env:RUNNER_TEMP "postbox-upgrade-$id"
$local = Join-Path $root 'local'
$profile = Join-Path $root 'profile'
$data = Join-Path $local 'Messages'
$tag = '0000000000000526'
New-Item "$data/msg-cache-$tag", "$profile/Desktop", "$profile/Documents" -ItemType Directory -Force | Out-Null
Set-Content "$data/account-tag.txt" $tag -NoNewline
@{data=@(@{jid='verify-alpha';name='Existing conversation';kind='direct';last_message_ts='2026-01-01T12:34:00Z'})} | ConvertTo-Json -Depth 8 | Set-Content "$data/chats-$tag.json"
$text = 'This conversation survived the name change.'
$payloadText = @{data=@{messages=@(@{MsgID='before-rename';SenderName='Existing contact';Text=$text;Timestamp='2026-01-01T12:34:00Z';FromMe=$false})}} | ConvertTo-Json -Depth 8 -Compress
$cache = "$data/msg-cache-$tag/$CacheId.msg"
Set-Content $cache "wazig-msg-cache v2`n$tag`nverify-alpha`n$payloadText" -NoNewline
$cacheHash = (Get-FileHash $cache).Hash
New-Item 'HKCU:\Software\Messages' -Force | Out-Null
Set-ItemProperty 'HKCU:\Software\Messages' -Name FontScale -Type DWord -Value 105
Set-ItemProperty 'HKCU:\Software\Messages' -Name Theme -Type DWord -Value 1
$hosts = "$env:SystemRoot/System32/drivers/etc/hosts"
$originalHosts = [IO.File]::ReadAllBytes($hosts)
$server = $null
$cert = $null
$app = $null
$exe = [IO.Path]::GetFullPath("$env:LOCALAPPDATA/Programs/Messages/Messages.exe")
$ctl = "$env:LOCALAPPDATA/Programs/Messages/wazigctl.exe"
$shortcut = "$env:APPDATA/Microsoft/Windows/Start Menu/Programs/Postbox.lnk"
$caseResult = @{status='failed';red=[bool]$RedControl;version=$Version;commit=$env:GITHUB_SHA;payload_sha256=(Get-FileHash $Payload).Hash}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class UpgradeWindow {
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr window, uint message, UIntPtr wparam, IntPtr lparam);
}
'@
function Capture-Upgrade([string]$Name, $Session, $Process) {
    $Process.Refresh()
    $title = $Process.MainWindowTitle
    $title | Set-Content (Join-Path $Evidence "$Name.title.txt")
    Read-Control $Session status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence "$Name.status.json")
    Read-Control $Session messages -Arguments @('verify-alpha') | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence "$Name.messages.json")
    $bounds = [Windows.Forms.SystemInformation]::VirtualScreen
    $image = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($image)
    try {
        $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
        $image.Save((Join-Path $Evidence "$Name.png"), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $image.Dispose() }
    return $title
}
try {
    & msiexec /i $Msi /qn /norestart /L*V "$Evidence/install.log" | Out-Null
    Assert-That ($LASTEXITCODE -eq 0) 'Original release MSI failed to install'
    Assert-That (Test-Path $exe) 'Original MSI did not install Messages.exe'
    $oldHash = (Get-FileHash $exe).Hash
    Copy-Item $Payload "$root/update.zip"
    @{tag="v$Version"} | ConvertTo-Json | Set-Content "$root/offer.json"
    & openssl req -x509 -newkey rsa:2048 -nodes -keyout "$root/key.pem" -out "$root/cert.pem" -days 1 -subj '/CN=api.github.com' -addext 'subjectAltName=DNS:api.github.com' 2> "$Evidence/certificate.log"
    Assert-That ($LASTEXITCODE -eq 0) 'Unable to create disposable HTTPS fixture certificate'
    $cert = Import-Certificate -FilePath "$root/cert.pem" -CertStoreLocation Cert:\LocalMachine\Root
    [IO.File]::AppendAllText($hosts, "`n127.0.0.1 api.github.com`n")
    ipconfig /flushdns | Out-Null
    $server = Start-Process python -ArgumentList @("`"$PSScriptRoot/fake-github-updates.py`"", '--root', "`"$root`"") -PassThru -RedirectStandardError "$Evidence/server.log"
    $null = Wait-Until { if ($server.HasExited) { throw 'HTTPS fixture exited' }; Test-Path "$root/ready" } 'HTTPS fixture'
    $start = [Diagnostics.ProcessStartInfo]::new($exe)
    $start.UseShellExecute = $false
    $start.Environment['LOCALAPPDATA'] = $local
    $start.Environment['USERPROFILE'] = $profile
    $start.Environment['USERNAME'] = "verify-$id"
    foreach ($name in @('DEEPGRAM_API_KEY','OPENROUTER_API_KEY','OPENROUTER_MODEL','WA_BRIDGE_KEY','WAZIG_FAKE_VERSION','WAZIG_HUB_URL','WAZIG_HUB_TOKEN','WAZIG_VERIFY_ROOT')) { $null = $start.Environment.Remove($name) }
    $app = [Diagnostics.Process]::Start($start)
    $oldPid = $app.Id
    $session = @{ctl=$ctl;username="verify-$id"}
    $null = Wait-Until { $app.Refresh(); if ($app.HasExited) { throw 'Original app exited early' }; $app.MainWindowHandle -ne [IntPtr]::Zero } 'old product window'
    $oldTitle = Capture-Upgrade before $session $app
    Assert-That ($oldTitle -match ' - Wazig v0\.9\.216$') 'Original release identity mismatch'
    $beforeMessages = Get-Content "$Evidence/before.messages.json" -Raw | ConvertFrom-Json
    Assert-That ($beforeMessages.messages[0].text -ceq $text) 'Original app did not display the existing chat'
    $null = Wait-Until { Test-Path "$local/Wazig/update/ready.txt" } 'original updater downloads and verifies package' 90
    Assert-That (((Get-Content "$local/Wazig/update/ready.txt")[0]) -ceq "v$Version") 'Original updater staged wrong version'
    $caseResult.download_verified = $true
    Assert-That ([UpgradeWindow]::PostMessageW($app.MainWindowHandle, 273, [UIntPtr]2053, [IntPtr]::Zero)) 'Unable to choose original in-app Update action'
    $null = Wait-Until { $app.Refresh(); $app.HasExited } 'original updater completes swap and relaunches' 60
    $app = Wait-Until {
        $owned = @(Get-Process | Where-Object { $_.Id -ne $oldPid -and $_.Path -eq $exe })
        if ($owned.Count -gt 1) { throw 'Multiple replacement processes' }
        if ($owned.Count -eq 1 -and $owned[0].MainWindowHandle -ne [IntPtr]::Zero) { $owned[0] }
    } 'replacement app window' 30
    $newTitle = Capture-Upgrade after $session $app
    Assert-That ($newTitle -cmatch (' - Postbox v' + [regex]::Escape($Version) + '$')) 'POSTBOX_TITLE_MISSING'
    Assert-That ((Get-FileHash $exe).Hash -ne $oldHash) 'Original binary did not change through the updater'
    $afterMessages = Get-Content "$Evidence/after.messages.json" -Raw | ConvertFrom-Json
    Assert-That ($afterMessages.messages[0].id -ceq 'before-rename' -and $afterMessages.messages[0].text -ceq $text) 'Existing chat changed during upgrade'
    Assert-That ((Get-FileHash $cache).Hash -eq $cacheHash) 'Existing cache bytes changed during rename'
    $preferences = Get-ItemProperty 'HKCU:\Software\Messages'
    Assert-That ($preferences.FontScale -eq 105 -and $preferences.Theme -eq 1) 'Saved preferences did not survive upgrade'
    $registered = @(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object DisplayName -eq 'Postbox')
    Assert-That ($registered.Count -eq 1) 'Installed app still has its old product name'
    Assert-That (Test-Path $shortcut) 'Old in-app update did not produce Postbox shortcut'
    $shell = New-Object -ComObject WScript.Shell
    Assert-That ($shell.CreateShortcut($shortcut).TargetPath -eq $exe) 'Renamed shortcut points at a different installation'
    Assert-That (-not (Test-Path "$env:APPDATA/Microsoft/Windows/Start Menu/Programs/Messages.lnk")) 'Legacy shortcut remains'
    $next = [version]$Version
    $nextTag = "v$($next.Major).$($next.Minor).$($next.Build + 1)"
    @{tag=$nextTag} | ConvertTo-Json | Set-Content "$root/offer.json"
    Assert-That ([UpgradeWindow]::PostMessageW($app.MainWindowHandle, 273, [UIntPtr]2052, [IntPtr]::Zero)) 'Unable to check next update'
    $null = Wait-Until { (Get-Content "$data/launch-log.txt" -Raw) -match ([regex]::Escape("update: card offered $nextTag")) } 'renamed app finds next update' 90
    $null = Capture-Upgrade next-update $session $app
    $paths = @(Get-Content "$root/requests.jsonl" | ForEach-Object { ($_ | ConvertFrom-Json).path })
    Assert-That ($paths -contains '/repos/valentinyeo/wazig/releases/latest') 'Original update route was not exercised'
    Assert-That ($paths -contains '/repos/valentinyeo/postbox/releases/latest') 'Renamed update route was not exercised'
    $caseResult.status = 'passed'
    $caseResult.old_title = $oldTitle
    $caseResult.new_title = $newTitle
    $caseResult.old_sha256 = $oldHash
    $caseResult.new_sha256 = (Get-FileHash $exe).Hash
    $caseResult.messages_preserved = $true
    $caseResult.settings_preserved = $true
    $caseResult.shortcut_preserved = $true
    $caseResult.next_update = $nextTag
} catch {
    $caseResult.error = $_.Exception.Message
    if ($RedControl -and $_.Exception.Message -ceq 'POSTBOX_TITLE_MISSING') {
        $caseResult.status = 'expected-red'
        'OLD_NAME_RED_PROVEN' | Set-Content "$Evidence/red-control.txt"
    } else { throw }
} finally {
    foreach ($owned in @(Get-Process | Where-Object { $_.Path -eq $exe })) {
        $null = $owned.CloseMainWindow()
        if (-not $owned.WaitForExit(10000)) { $owned.Kill(); $owned.WaitForExit() }
    }
    if ($null -ne $server -and -not $server.HasExited) { $server.Kill(); $server.WaitForExit() }
    [IO.File]::WriteAllBytes($hosts, $originalHosts)
    ipconfig /flushdns | Out-Null
    if ($null -ne $cert) { Remove-Item "Cert:\LocalMachine\Root\$($cert.Thumbprint)" }
    if (Test-Path "$root/requests.jsonl") { Copy-Item "$root/requests.jsonl" "$Evidence/requests.jsonl" }
    if (Test-Path "$data/launch-log.txt") { Copy-Item "$data/launch-log.txt" "$Evidence/launch-log.txt" }
    & msiexec /x $Msi /qn /norestart | Out-Null
    if (Test-Path $shortcut) { Remove-Item $shortcut }
    Remove-Item 'HKCU:\Software\Messages' -Recurse -Force
    Remove-Item $root -Recurse -Force
    $caseResult.cleanup = (-not (Test-Path $root)) -and (-not (Test-Path 'HKCU:\Software\Messages'))
    $caseResult | ConvertTo-Json -Depth 8 | Set-Content "$Evidence/result.json"
}
Assert-That ($caseResult.cleanup) 'Disposable upgrade profile survived cleanup'
if ($RedControl) { Assert-That ($caseResult.status -ceq 'expected-red') 'Original product unexpectedly passed rename journey' }
else { Assert-That ($caseResult.status -ceq 'passed') 'Postbox upgrade journey did not pass' }
