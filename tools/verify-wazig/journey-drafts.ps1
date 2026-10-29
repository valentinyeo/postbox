Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ComposerRepaint {
    [DllImport("user32.dll")] public static extern bool InvalidateRect(IntPtr hwnd, IntPtr rect, bool erase);
    [DllImport("user32.dll")] public static extern bool UpdateWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
}
'@
Invoke-PaletteCommand $session 'Compose message'
$empty = Read-Control $session status
$dpi = [int][VerifyWindow]::GetDpiForWindow($app.MainWindowHandle)
$oneLineHeight = [int][Math]::Floor((44 * $dpi + 48) / 96)
Save-Screen $session composer-empty
Send-Keys $session 'Draft probe'
$null = Wait-Until { (Read-Edit $compose) -eq 'Draft probe' } 'composer probe typed'
Save-Screen $session composer-typed
$editHandle = [IntPtr]$compose.Current.NativeWindowHandle
Assert-That ([ComposerRepaint]::InvalidateRect($editHandle, [IntPtr]::Zero, $false)) 'Composer redraw request failed'
[ComposerRepaint]::UpdateWindow($editHandle) | Out-Null
Save-Screen $session composer-repainted
$dirty = [Drawing.Bitmap]::new((Join-Path $Evidence 'composer-typed.png'))
$clean = [Drawing.Bitmap]::new((Join-Path $Evidence 'composer-repainted.png'))
try {
    $bounds = $compose.Current.BoundingRectangle
    $desktop = [Windows.Forms.SystemInformation]::VirtualScreen
    $pattern = $compose.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
    $points = [double]$pattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
    $belowText = [int][Math]::Ceiling($bounds.Top - $desktop.Top + 8 * $dpi / 96 + $points * $dpi / 72 + 3)
    $different = 0
    for ($y = $belowText; $y -lt [int]$bounds.Bottom - $desktop.Top - 1; $y++) {
        for ($x = [int]$bounds.Left - $desktop.Left + 2; $x -lt [int]$bounds.Right - $desktop.Left - 2; $x++) {
            if ($dirty.GetPixel($x, $y).ToArgb() -ne $clean.GetPixel($x, $y).ToArgb()) { $different++ }
        }
    }
    Assert-That ($different -eq 0) 'Typed composer left stale placeholder pixels below its text'
} finally { $dirty.Dispose(); $clean.Dispose() }
Assert-That ($empty.composer.box.bottom - $empty.composer.box.top -eq $oneLineHeight) 'Empty composer must start one line tall despite an old saved height'
$measurements = [ordered]@{ empty_height = $empty.composer.box.bottom - $empty.composer.box.top; expected_height = $oneLineHeight; stale_pixels = $different }
Send-Keys $session '^a{BACKSPACE}'
$null = Wait-Until { (Read-Edit $compose) -eq '' } 'composer probe cleared'
$reset = Read-Control $session status
Assert-That ($reset.composer.box.bottom - $reset.composer.box.top -eq $oneLineHeight) 'Cleared composer must return to one line'
$measurements['cleared_height'] = $reset.composer.box.bottom - $reset.composer.box.top
Send-Keys $session 'One'
Send-Keys $session '+{ENTER}Two'
$null = Wait-Until { (Read-Control $session status).composer.lines -eq 2 } 'two-line composer'
$two = Read-Control $session status
Assert-That ($two.composer.box.bottom - $two.composer.box.top -gt $oneLineHeight) 'Composer did not grow with its second line'
Save-Screen $session composer-two-lines
for ($line = 0; $line -lt 30; $line++) { Send-Keys $session '+{ENTER}More' }
$null = Wait-Until { (Read-Control $session status).composer.lines -eq 32 } 'long composer'
$long = Read-Control $session status
Assert-That ($long.composer.box.bottom - $long.composer.box.top -eq [int][Math]::Floor((240 * $dpi + 48) / 96)) 'Composer did not stop at its existing height limit'
$measurements['two_line_height'] = $two.composer.box.bottom - $two.composer.box.top
$measurements['capped_height'] = $long.composer.box.bottom - $long.composer.box.top
Save-Screen $session composer-long
Send-Keys $session '^{HOME}'
$firstVisible = [ComposerRepaint]::SendMessageW($editHandle, 0xCE, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
Assert-That ($firstVisible -eq 0) 'Long composer did not scroll to its beginning'
Save-Screen $session composer-scroll-start
Send-Keys $session '^{END}'
$lastVisible = [ComposerRepaint]::SendMessageW($editHandle, 0xCE, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
Assert-That ($lastVisible -gt $firstVisible) 'Long composer did not scroll internally'
$measurements['first_visible_line'] = $firstVisible
$measurements['last_visible_line'] = $lastVisible
Save-Screen $session composer-scroll-end
Send-Keys $session '^a{BACKSPACE}'
$null = Wait-Until { (Read-Edit $compose) -eq '' } 'long composer cleared'
$finalEmpty = Read-Control $session status
Assert-That ($finalEmpty.composer.box.bottom - $finalEmpty.composer.box.top -eq $oneLineHeight) 'Long composer did not shrink after clearing'
$measurements['long_cleared_height'] = $finalEmpty.composer.box.bottom - $finalEmpty.composer.box.top
$measurements | ConvertTo-Json | Set-Content (Join-Path $Evidence 'composer-behavior.json')
Save-Screen $session composer-cleared
Send-Keys $session 'Verification draft'
Send-Keys $session '{HOME}{RIGHT 12}+{END}'
Send-Keys $session 'text'
$null = Wait-Until { (Read-Edit $compose) -eq 'Verificationtext' } 'Shift-arrow selection replacement'
Send-Keys $session '^z'
$null = Wait-Until { (Read-Edit $compose) -eq 'Verification draft' } 'native undo'
Send-Keys $session '^y'
$null = Wait-Until { (Read-Edit $compose) -eq 'Verificationtext' } 'native redo'
Send-Keys $session '^a'
Send-Keys $session 'Verification draft'
Send-Keys $session '^{BACKSPACE}'
$null = Wait-Until { (Read-Edit $compose) -eq 'Verification ' } 'Ctrl-Backspace word deletion'
Send-Keys $session 'draft'
Send-Keys $session '^a'
Send-Keys $session '^c'
Send-Keys $session '^v'
$null = Wait-Until { (Read-Edit $compose) -eq 'Verification draft' } 'Ctrl-V pastes exactly once'
Send-Keys $session '^a'
Send-Keys $session '+{INSERT}'
$null = Wait-Until { (Read-Edit $compose) -eq 'Verification draft' } 'Shift-Insert uses the guarded paste path'
Save-Screen $session paste
Send-Keys $session '{END}'
Send-Keys $session '+{ENTER}'
Send-Keys $session 'second'
$null = Wait-Until { (Read-Edit $compose) -eq "Verification draft`nsecond" } 'Shift-Enter multiline input'
Send-Keys $session '^a'
Send-Keys $session 'Verification draft'
Send-Keys $session '^{TAB}'
Assert-That ((Read-Edit $compose) -eq '') 'Draft leaked to the next chat'
Send-Keys $session '^+{TAB}'
$null = Wait-Until { (Read-Edit $compose) -eq 'Verification draft' } 'restored per-chat draft'
$draft = Join-Path $messages 'drafts.json'
$null = Wait-Until { (Test-Path $draft) -and (Get-Content $draft -Raw).Contains('Verification draft') } 'persisted draft'
Copy-Item $draft (Join-Path $Evidence 'drafts.json')
Save-Screen $session after
foreach ($theme in @('Graphite')) {
    Send-Keys $session '^k'
    Send-Keys $session "Theme: $theme"
    Send-Keys $session '{ENTER}'
    $themeId = 'amoled'
    $null = Wait-Until { (Read-Control $session status).theme -eq $themeId } 'composer theme applied'
    foreach ($windowSize in @('wide', 'narrow')) {
        if ($windowSize -eq 'wide') {
            [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
        } else {
            [VerifyWindow]::ShowWindow($app.MainWindowHandle, 9) | Out-Null
            $dpi = [VerifyWindow]::GetDpiForWindow($app.MainWindowHandle)
            $width = [int][Math]::Floor((600 * $dpi + 48) / 96)
            $height = [int][Math]::Floor((700 * $dpi + 48) / 96)
            Assert-That ([VerifyWindow]::SetWindowPos($app.MainWindowHandle, [IntPtr]::Zero, 0, 0, $width, $height, 6)) 'Cannot resize narrow verification window'
            $null = Wait-Until { [Math]::Abs((Get-Window $session).Current.BoundingRectangle.Width - $width) -le 1 } 'narrow native window'
            $narrowBox = (Read-Control $session status).composer.box
            Assert-That (($narrowBox.right - $narrowBox.left) -lt 360 * $dpi / 96) 'Composer did not reach narrow width'
        }
        Send-Keys $session '^a'
        Send-Keys $session 'One'
        $null = Wait-Until { (Read-Control $session status).composer.lines -eq 1 } 'one composer line'
        $baseline = Assert-ComposerLayout $session "composer-$themeId-$windowSize-one" 1
        Send-Keys $session '+{ENTER}'
        Send-Keys $session 'Two'
        Send-Keys $session '+{ENTER}'
        Send-Keys $session 'Three'
        $null = Wait-Until { (Read-Control $session status).composer.lines -eq 3 } 'three composer lines'
        $null = Assert-ComposerLayout $session "composer-$themeId-$windowSize-multiline" 3 $baseline
    }
}
