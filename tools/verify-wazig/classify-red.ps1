param(
    [Parameter(Mandatory)] [string]$Feature,
    [Parameter(Mandatory)] [string]$Evidence,
    [Parameter(Mandatory)] [int]$ExitCode,
    [string]$PassedMessage = 'journey passed, so it does not show the bug',
    [string]$ExpectedCheck = ''
)
$ErrorActionPreference = 'Stop'
$expectedArgs = if ($ExpectedCheck) { @('--expected-check', $ExpectedCheck) } else { @() }
& python "$PSScriptRoot/classify_red.py" --feature $Feature --evidence $Evidence --exit-code $ExitCode --passed-message $PassedMessage @expectedArgs
if ($LASTEXITCODE -ne 0) { throw "Journey red rejected for $Feature; see classifier diagnostic" }
