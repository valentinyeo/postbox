$records = @()
foreach ($themeName in @('amoled', 'green')) {
    Invoke-PaletteCommand $session $(if ($themeName -eq 'amoled') { 'Theme: AMOLED black' } else { 'Theme: Green' })
    $null = Wait-Until { (Read-Control $session status).theme -ceq $themeName } 'sidebar theme applied'
    Invoke-PaletteCommand $session 'Search chats'
    Send-Keys $session '{ESC}'
    $null = Wait-Until { (Read-Control $session status).search -ceq '' } 'sidebar search cleared'
    $window = Get-Window $session
    $paletteCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'MessagesPalette')
    $null = Wait-Until { $null -eq $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $paletteCondition) } 'command palette closed before the sidebar screenshot'
    $handle = [IntPtr]$window.Current.NativeWindowHandle
    $origin = [VerifyWindow+Point]::new()
    $client = [VerifyWindow+Rect]::new()
    Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'Sidebar client origin missing'
    Assert-That ([VerifyWindow]::GetClientRect($handle, [ref]$client)) 'Sidebar client bounds missing'
    $dpi = [int][VerifyWindow]::GetDpiForWindow($handle)
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, '1016')
    $list = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
    Assert-That ($null -ne $list) 'Sidebar list missing'
    $listBounds = $list.Current.BoundingRectangle
    $canvasCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'WacliMessageCanvas')
    $canvas = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $canvasCondition)
    Assert-That ($null -ne $canvas) 'Sidebar comparison canvas missing'
    $metricsPath = Join-Path $messages 'text-metrics.json'
    $null = Wait-Until {
        if (-not (Test-Path $metricsPath)) { return $false }
        $metrics = Get-Content $metricsPath -Raw | ConvertFrom-Json
        $bounds = $canvas.Current.BoundingRectangle
        $metrics.canvas.width -eq [int]$bounds.Width -and $metrics.canvas.height -eq [int]$bounds.Height
    } 'sidebar fixture message painted'
    $state = Read-Control $session status
    Assert-That ($state.chat_count -eq 2 -and $state.selected.id -ceq 'verify-alpha') 'Sidebar fixture selection changed'
    $desktop = [Windows.Forms.SystemInformation]::VirtualScreen
    $x = $origin.X - $desktop.Left
    $y = $origin.Y - $desktop.Top
    $edge = [int]$canvas.Current.BoundingRectangle.Left - $desktop.Left - 1
    $name = "sidebar-$themeName"
    Save-Screen $session $name
    Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence "$name.messages.json")
    $records += [ordered]@{
        theme = $themeName; dpi = $dpi; screenshot = "$name.png"
        client = @($x, $y, $x + $client.Right, $y + $client.Bottom)
        edge = $edge
        list = @([int]$listBounds.Left - $desktop.Left, [int]$listBounds.Top - $desktop.Top, [int]$listBounds.Right - $desktop.Left, [int]$listBounds.Bottom - $desktop.Top)
    }
}
$records | ConvertTo-Json -Depth 12 -AsArray | Set-Content (Join-Path $Evidence 'sidebar-layout.json')
Save-Screen $session after
