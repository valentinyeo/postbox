$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'Audio setup requires a disposable GitHub-hosted runner' }
$folder = Join-Path $env:RUNNER_TEMP 'verify-audio'
New-Item $folder -ItemType Directory -Force | Out-Null
$archive = Join-Path $folder 'scream.zip'
Invoke-WebRequest 'https://github.com/duncanthrax/scream/releases/download/4.0/Scream4.0.zip' -OutFile $archive
if ((Get-FileHash $archive -Algorithm SHA256).Hash -cne 'FA33E25F9A46C61E4E0CD83362C51C3D2A45C6FE4091AAD7507E240E40F1A520') { throw 'Audio driver archive digest mismatch' }
Expand-Archive $archive $folder -Force
$driver = Join-Path $folder 'Install/driver/x64'
$signature = Get-AuthenticodeSignature (Join-Path $driver 'Scream.sys')
if (-not $signature.SignerCertificate) { throw 'Audio driver has no signing certificate' }
$certificate = Join-Path $folder 'publisher.cer'
[IO.File]::WriteAllBytes($certificate, $signature.SignerCertificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
Import-Certificate -FilePath $certificate -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
$options = 'HKLM:\SYSTEM\CurrentControlSet\Services\Scream\Options'
New-Item $options -Force | Out-Null
New-ItemProperty $options -Name UnicastIPv4 -PropertyType String -Value '127.0.0.1' -Force | Out-Null
New-ItemProperty $options -Name UnicastPort -PropertyType DWord -Value 4010 -Force | Out-Null
& (Join-Path $folder 'Install/helpers/devcon-x64.exe') install (Join-Path $driver 'Scream.inf') '*Scream'
if ($LASTEXITCODE -ne 0) { throw "Audio driver installation failed: $LASTEXITCODE" }
Set-Service AudioEndpointBuilder -StartupType Automatic
Start-Service AudioEndpointBuilder
Set-Service Audiosrv -StartupType Automatic
Start-Service Audiosrv
$device = @(Get-PnpDevice -Class MEDIA | Where-Object { $_.FriendlyName -eq 'Scream (WDM)' -and $_.Status -eq 'OK' })
if ($device.Count -ne 1) { throw 'Isolated audio device missing or unhealthy' }
$device | Format-List | Out-String | Write-Output
Write-Output 'ISOLATED_AUDIO_READY'
