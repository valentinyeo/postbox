$ErrorActionPreference = 'Stop'
$attempts = 4
for ($i = 1; $i -le $attempts; $i++) {
    choco install ffmpeg --yes --no-progress
    if ($LASTEXITCODE -eq 0 -and (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        ffmpeg -version | Select-Object -First 1
        exit 0
    }
    Write-Host "FFmpeg install attempt $i of $attempts did not give a working ffmpeg"
    if ($i -lt $attempts) { Start-Sleep -Seconds (10 * $i) }
}
throw 'FFmpeg is missing after all install attempts'
