param(
    [Parameter(Mandatory)] [string]$Feature,
    [Parameter(Mandatory)] [string]$Evidence,
    [Parameter(Mandatory)] [int]$ExitCode,
    [string]$PassedMessage = 'repro passed on base, so it does not reproduce the bug'
)
if ($ExitCode -eq 0) { throw $PassedMessage }
if (-not (Test-Path (Join-Path $Evidence 'journey-started.txt')) -or -not (Test-Path (Join-Path $Evidence 'failure.txt'))) { throw 'failed before the journey ran' }
$failure = Get-Content (Join-Path $Evidence 'failure.txt') -Raw
if ([string]::IsNullOrWhiteSpace($failure) -or $failure.StartsWith("${Feature}: App exited", [StringComparison]::OrdinalIgnoreCase) -or $failure -match 'Unknown verification journey|Hosted runner|Verification runs only|Timed out:\s*main window') { throw 'failed before the journey ran' }
Write-Host $failure
