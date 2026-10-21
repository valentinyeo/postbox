param($Session, [string]$Bin)
$ErrorActionPreference = 'Stop'
$evidence = $Session.evidence
$window = Get-Window $Session
$bounds = $window.Current.BoundingRectangle
$native = [ordered]@{ x = [int]$bounds.X; y = [int]$bounds.Y; width = [int]$bounds.Width; height = [int]$bounds.Height }
$native | ConvertTo-Json | Set-Content (Join-Path $evidence 'native-capture.json')
$image = [Drawing.Bitmap]::new($native.width, $native.height)
$graphics = [Drawing.Graphics]::FromImage($image)
try {
    $graphics.CopyFromScreen($native.x, $native.y, 0, 0, $image.Size)
    $image.Save((Join-Path $evidence 'wazig.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally {
    $graphics.Dispose()
    $image.Dispose()
}
& node "$PSScriptRoot/chrome-text.cjs" $evidence (Resolve-Path $Bin).Path
if ($LASTEXITCODE -ne 0) { throw 'Chrome comparison failed' }
$metrics = Get-Content (Join-Path $evidence 'text-metrics.json') -Raw | ConvertFrom-Json
$chrome = Get-Content (Join-Path $evidence 'chrome.json') -Raw | ConvertFrom-Json
$wazig = [Drawing.Bitmap]::new((Join-Path $evidence 'wazig.png'))
$browser = [Drawing.Bitmap]::new((Join-Path $evidence 'chrome.png'))
$cropWidth = [int][Math]::Ceiling([Math]::Max($metrics.paragraph.width, $chrome.paragraph.width))
$cropHeight = [int][Math]::Ceiling([Math]::Max($metrics.paragraph.height, $chrome.paragraph.height))
$panelWidth = [Math]::Max($wazig.Width, $cropWidth * 3)
$topHeight = [Math]::Max($wazig.Height, $browser.Height)
$combined = [Drawing.Bitmap]::new($panelWidth * 2, $topHeight + $cropHeight * 3 + 100)
$g = [Drawing.Graphics]::FromImage($combined)
$labelFont = [Drawing.Font]::new('Segoe UI', 14)
try {
    $g.Clear([Drawing.Color]::FromArgb(35, 35, 35))
    $g.DrawString('Wazig release / DirectWrite', $labelFont, [Drawing.Brushes]::White, 8, 5)
    $g.DrawString("Chrome $($chrome.chrome_version) / bundled Plex", $labelFont, [Drawing.Brushes]::White, $panelWidth + 8, 5)
    $g.DrawImageUnscaled($wazig, 0, 32)
    $g.DrawImageUnscaled($browser, $panelWidth, 32)
    $label = "Paragraph 3x nearest-neighbor: $($metrics.body.px)px / weight $($metrics.body.weight) / line $($metrics.body.line_height)px"
    $g.DrawString($label, $labelFont, [Drawing.Brushes]::White, 8, $topHeight + 38)
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
    $rectangles = @(
        @{ image = $wazig; x = [int]$metrics.paragraph.x - $native.x; y = [int]$metrics.paragraph.y - $native.y; width = [int]$metrics.paragraph.width; height = [int]$metrics.paragraph.height; name = 'wazig' },
        @{ image = $browser; x = [int]$chrome.paragraph.x; y = [int]$chrome.paragraph.y; width = [int]$chrome.paragraph.width; height = [int]$chrome.paragraph.height; name = 'chrome' }
    )
    for ($i = 0; $i -lt 2; $i++) {
        $r = $rectangles[$i]
        if ($r.x -lt 0 -or $r.y -lt 0 -or $r.x + $r.width -gt $r.image.Width -or $r.y + $r.height -gt $r.image.Height) { throw 'Paragraph crop outside screenshot' }
        $source = [Drawing.Rectangle]::new($r.x, $r.y, $r.width, $r.height)
        $crop = $r.image.Clone($source, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $zoom = [Drawing.Bitmap]::new($crop.Width * 3, $crop.Height * 3)
        $zg = [Drawing.Graphics]::FromImage($zoom)
        try {
            $crop.Save((Join-Path $evidence "$($r.name)-paragraph.png"), [Drawing.Imaging.ImageFormat]::Png)
            $zg.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
            $zg.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
            $zg.DrawImage($crop, [Drawing.Rectangle]::new(0, 0, $zoom.Width, $zoom.Height), 0, 0, $crop.Width, $crop.Height, [Drawing.GraphicsUnit]::Pixel)
            $zoom.Save((Join-Path $evidence "$($r.name)-paragraph-3x.png"), [Drawing.Imaging.ImageFormat]::Png)
            $g.DrawImageUnscaled($zoom, $i * $panelWidth, $topHeight + 72)
        } finally {
            $zg.Dispose()
            $zoom.Dispose()
            $crop.Dispose()
        }
    }
    $combined.Save((Join-Path $evidence 'text-comparison.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally {
    $labelFont.Dispose()
    $g.Dispose()
    $combined.Dispose()
    $wazig.Dispose()
    $browser.Dispose()
}
'ISSUE-462 COMPARISON CAPTURED: release window, installed Chrome, identical metrics and 3x crops' | Set-Content (Join-Path $evidence 'comparison-result.txt')
