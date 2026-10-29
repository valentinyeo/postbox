Invoke-PaletteCommand $session 'Theme: Graphite' action
$null = Wait-Until { (Read-Control $session status).theme -eq 'amoled' } 'green theme'
$preferences = "HKCU:\Software\MessagesVerification\$id\Software\Messages"
Assert-That ((Get-ItemProperty $preferences).Theme -eq 1) 'Theme preference was not saved'
Assert-That ($null -eq (Get-ItemProperty $preferences).FontScale) 'Fresh fixture already has a saved scale'
Send-Keys $session 'Scale probe'
$textPattern = $compose.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
$baselinePoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
Assert-That ($baselinePoints -gt 0) 'Composer font size is not readable through UI Automation'
Invoke-PaletteCommand $session 'Make text larger'
$null = Wait-Until { (Get-ItemProperty $preferences).FontScale -eq 92 } 'larger text scale persisted'
$larger = (Get-ItemProperty $preferences).FontScale
$largerPoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
Assert-That ($largerPoints -gt $baselinePoints) 'Larger text did not increase the UI Automation font size'
Save-Screen $session text-larger
Send-Keys $session '^0'
$null = Wait-Until { (Get-ItemProperty $preferences).FontScale -eq 82 } 'default text scale restored'
$resetPoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
Assert-That ($resetPoints -eq $baselinePoints) 'Reset did not restore the UI Automation font size'
@{ initial_saved = $false; larger = $larger; reset = (Get-ItemProperty $preferences).FontScale; baseline_points = $baselinePoints; larger_points = $largerPoints; reset_points = $resetPoints } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'text-scale.json')
Send-Keys $session '^a{BACKSPACE}'
$null = Wait-Until { (Read-Edit $compose) -eq '' } 'scale probe cleared'
Save-Screen $session after
