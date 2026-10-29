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
