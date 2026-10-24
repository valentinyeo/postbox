$launch = Get-Content (Join-Path $messages 'launch-log.txt') -Raw
Assert-That ($launch.Contains('whatsapp backend: wacli (URL not configured)') -and -not $launch.Contains('message backend: hub')) 'Unconfigured hub did not select direct fallback'
Add-Content (Join-Path $Evidence 'fallback-proof.log') 'hub no-url-direct-fallback PASS'
function Save-SearchPill([string]$Name) {
    $bounds = $search.Current.BoundingRectangle
    $dpi = [VerifyWindow]::GetDpiForWindow([IntPtr]$search.Current.NativeWindowHandle)
    Assert-That ($dpi -gt 0) 'Cannot measure search DPI'
    $height = [int]$bounds.Height + 2
    $diameter = [Math]::Min([Math]::Floor((56 * $dpi + 48) / 96), $height)
    $inset = [int][Math]::Ceiling($diameter / 2)
    $left = [int]$bounds.Left - $inset
    $top = [int]$bounds.Top - 1
    $width = [int]$bounds.Width + 2 * $inset
    $image = [Drawing.Bitmap]::new($width, $height)
    $graphics = [Drawing.Graphics]::FromImage($image)
    try {
        $graphics.CopyFromScreen($left, $top, 0, 0, $image.Size)
        $image.Save((Join-Path $Evidence "search-center-$Name.png"), [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $image.Dispose()
    }
    return @{
        pill = @(0, 0, $width, $height)
        edit = @($inset, 1, ($width - $inset), ($height - 1))
        screen_pill = @($left, $top, ($left + $width), ($top + $height))
        uia_edit = @($bounds.Left, $bounds.Top, $bounds.Right, $bounds.Bottom)
        dpi = $dpi; focused = $search.Current.HasKeyboardFocus; text = (Read-Edit $search)
    }
}
Invoke-PaletteCommand $session 'Compose message'
$null = Wait-Until { -not $search.Current.HasKeyboardFocus -and (Read-Edit $search) -eq '' } 'empty unfocused search'
$centerLayout = @{ placeholder = (Save-SearchPill placeholder) }
Send-Keys $session '^f'
Send-Keys $session 'Beta'
$null = Wait-Until { (Read-Control $session status).chat_count -eq 1 } 'one filtered chat'
$state = Read-Control $session status
Assert-That ($state.search -eq 'Beta' -and $state.selected.name -eq 'Verification Beta') 'Search did not select the matching fixture'
Save-Screen $session after
$null = Wait-Until { $search.Current.HasKeyboardFocus -and (Read-Edit $search) -eq 'Beta' } 'focused Beta search'
$centerLayout['typed'] = Save-SearchPill typed
$centerLayout | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Evidence 'search-center-layout.json')
Send-Keys $session '{ESC}'
$null = Wait-Until { (Read-Control $session status).chat_count -eq 2 } 'search cleared'
Send-Keys $session '^f'
Send-Keys $session 'NoSuchFixture'
$null = Wait-Until { (Read-Control $session status).chat_count -eq 0 } 'empty search result'
Save-Screen $session empty
Send-Keys $session '{ESC}'
$null = Wait-Until { (Read-Control $session status).chat_count -eq 2 } 'baseline restored'
