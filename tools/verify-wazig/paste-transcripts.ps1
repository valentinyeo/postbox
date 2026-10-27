param([Parameter(Mandatory)][string]$Evidence)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Paste proof runs only on GitHub Actions' }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$form = [Windows.Forms.Form]::new()
$form.Text = 'Transcript paste proof'
$form.Width = 850
$form.Height = 550
$form.TopMost = $true
$box = [Windows.Forms.TextBox]::new()
$box.Multiline = $true
$box.ScrollBars = 'Vertical'
$box.Dock = 'Fill'
$box.Font = [Drawing.Font]::new('Segoe UI', 13)
$form.Controls.Add($box)
$timer = [Windows.Forms.Timer]::new()
$timer.Interval = 400
$form.Add_Shown({
    $form.Activate()
    $box.Focus()
    $box.Paste()
    $timer.Start()
})
$timer.Add_Tick({
    $timer.Stop()
    [IO.File]::WriteAllText((Join-Path $Evidence 'transcripts-pasted.txt'), $box.Text, [Text.UTF8Encoding]::new($false))
    $bounds = $form.Bounds
    $image = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($image)
    try {
        $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
        $image.Save((Join-Path $Evidence 'transcripts-pasted.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $image.Dispose()
    }
    $form.Close()
})
try { [Windows.Forms.Application]::Run($form) } finally { $timer.Dispose(); $form.Dispose() }
