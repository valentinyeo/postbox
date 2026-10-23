$metrics = Join-Path $messages 'text-metrics.json'
$condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'WacliMessageCanvas')
$canvas = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
Assert-That ($null -ne $canvas) 'Message canvas missing'
$null = Wait-Until {
    if (-not (Test-Path $metrics)) { return $false }
    $painted = Get-Content $metrics -Raw | ConvertFrom-Json
    $bounds = $canvas.Current.BoundingRectangle
    $painted.canvas.width -eq [int]$bounds.Width -and $painted.canvas.height -eq [int]$bounds.Height
} 'fixture paragraph painted at final window size'
Copy-Item $metrics (Join-Path $Evidence 'text-metrics.json')
Save-Screen $session after
& "$PSScriptRoot/compare-text.ps1" -Session $session -Bin $Bin
