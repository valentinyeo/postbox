param(
    [Parameter(Mandatory)] [string]$Feature,
    [Parameter(Mandatory)] [string]$Evidence,
    [Parameter(Mandatory)] [int]$ExitCode,
    [string]$PassedMessage = 'repro passed on base, so it does not reproduce the bug'
)
$ErrorActionPreference = 'Stop'
& python "$PSScriptRoot/classify_red.py" --feature $Feature --evidence $Evidence --exit-code $ExitCode --passed-message $PassedMessage
if ($LASTEXITCODE -ne 0) { throw "Journey red rejected for $Feature; see classifier diagnostic" }
