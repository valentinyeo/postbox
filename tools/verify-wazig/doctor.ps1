param([Parameter(Mandatory)][string]$Evidence)
. "$PSScriptRoot/harness.ps1"
Invoke-Doctor (Read-Session $Evidence)
