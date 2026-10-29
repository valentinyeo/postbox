$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'Audio setup requires a disposable GitHub-hosted runner' }
$folder = Join-Path $env:RUNNER_TEMP 'verify-audio'
New-Item $folder -ItemType Directory -Force | Out-Null
$archive = Join-Path $folder 'audio.zip'
Invoke-WebRequest 'https://github.com/VirtualDrivers/Virtual-Audio-Driver/releases/download/25.7.14/Virtual.Audio.Driver.Signed.-.25.7.14.zip' -OutFile $archive
if ((Get-FileHash $archive -Algorithm SHA256).Hash -cne 'DD10560994DE65A7E587FB8B93C0D7E9838292D9C3566A0976C2786D727292BD') { throw 'Audio driver archive digest mismatch' }
Expand-Archive $archive $folder -Force
$driver = Join-Path $folder 'Virtual Audio Driver'
$signature = Get-AuthenticodeSignature (Join-Path $driver 'virtualaudiodriver.cat')
if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) { throw "Audio driver signature rejected: $($signature.Status)" }
$certificate = Join-Path $folder 'publisher.cer'
[IO.File]::WriteAllBytes($certificate, $signature.SignerCertificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
Import-Certificate -FilePath $certificate -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
$helper = Join-Path $folder 'devcon.zip'
Invoke-WebRequest 'https://github.com/duncanthrax/scream/releases/download/4.0/Scream4.0.zip' -OutFile $helper
if ((Get-FileHash $helper -Algorithm SHA256).Hash -cne 'FA33E25F9A46C61E4E0CD83362C51C3D2A45C6FE4091AAD7507E240E40F1A520') { throw 'Device helper archive digest mismatch' }
Expand-Archive $helper (Join-Path $folder 'helper') -Force
Set-Service AudioEndpointBuilder -StartupType Automatic
Start-Service AudioEndpointBuilder
Set-Service Audiosrv -StartupType Automatic
Start-Service Audiosrv
$inf = Join-Path $driver 'VirtualAudioDriver.inf'
pnputil /add-driver $inf /install
if ($LASTEXITCODE -ne 0) { throw "Audio driver staging failed: $LASTEXITCODE" }
$installer = Start-Process (Join-Path $folder 'helper/Install/helpers/devcon-x64.exe') -ArgumentList @('install', "`"$inf`"", 'ROOT\VirtualAudioDriver') -PassThru -RedirectStandardOutput (Join-Path $folder 'install.log') -RedirectStandardError (Join-Path $folder 'install-error.log')
try {
    if (-not $installer.WaitForExit(90000)) { throw 'Audio device installer stalled' }
    if ($installer.ExitCode -ne 0) { throw "Audio device installation failed: $($installer.ExitCode)" }
} finally {
    if (-not $installer.HasExited) { $installer.Kill(); $installer.WaitForExit() }
    Get-Content (Join-Path $folder 'install.log'), (Join-Path $folder 'install-error.log')
    Get-PnpDevice -Class MEDIA | Format-List | Out-String | Write-Output
    Get-Content "$env:WINDIR/INF/setupapi.dev.log" -Tail 120
}
$device = @(Get-PnpDevice -Class MEDIA | Where-Object { $_.FriendlyName -eq 'Virtual Audio Driver by MTT' -and $_.Status -eq 'OK' })
if ($device.Count -ne 1) { throw 'Isolated audio device missing or unhealthy; signature enforcement remains enabled' }
Write-Output 'ISOLATED_AUDIO_READY'
