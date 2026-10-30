Add-Type -Path (Join-Path $PSScriptRoot 'layout-capture.cs')
[LayoutCapture]::Display()
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 9) | Out-Null
Assert-That ([LayoutCapture]::MoveWindow($app.MainWindowHandle, 0, 0, 1920, 1032, $true)) 'Baseline viewport could not be set'
$bounds = (Get-Window $session).Current.BoundingRectangle
Assert-That ($bounds.Width -eq 1920 -and $bounds.Height -eq 1032) 'Baseline viewport differs from reported working area'
$preferences = "HKCU:\Software\MessagesVerification\$id\Software\Messages"
Assert-That ($null -eq (Get-ItemProperty $preferences -ErrorAction SilentlyContinue).FontScale) 'Baseline fixture has a saved font scale'
$null = Read-Control $session select -Arguments @('fixture-group@g.us', '--provider', 'whatsapp')
$null = Wait-Until { (Read-Control $session messages).chat.id -eq 'fixture-group@g.us' -and $compose.Current.IsEnabled } 'baseline fixture chat'
Invoke-PaletteCommand $session 'Compose message'
Send-Keys $session 'Scale probe'
$null = Wait-Until { (Read-Edit $compose) -ceq 'Scale probe' } 'baseline composer probe'
$pattern = $compose.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
$points = [double]$pattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
$dpi = [int][VerifyWindow]::GetDpiForWindow($app.MainWindowHandle)
$expectedPoints = [Math]::Floor((15 * 82 * $dpi + 4800) / 9600) * 72 / $dpi
Assert-That ($dpi -gt 0 -and [Math]::Abs($points - $expectedPoints) -lt 0.1) 'Published default font does not match 82 percent'
Assert-That ($null -eq (Get-ItemProperty $preferences -ErrorAction SilentlyContinue).FontScale) 'Baseline font preference was changed'
$state = Read-Control $session status
Assert-That ($state.version -ceq '0.9.224') 'Baseline runtime version differs'
Save-Screen $session font-baseline
@{ runtime_version = $state.version; initial_saved = $false; scale = 82; points = $points; dpi = $dpi; width = $bounds.Width; height = $bounds.Height; pid = $session.pid; start_ticks = $session.startTicks; root = $session.root; id = $session.id; exe_sha256 = $session.sha256 } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'font-baseline.json')
