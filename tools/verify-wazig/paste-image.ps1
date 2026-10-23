. "$PSScriptRoot/menus.ps1"

$pasteReferences = @((Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll').FullName) + @(
    [Drawing.Bitmap].Assembly.Location,
    [Drawing.Color].Assembly.Location,
    [Windows.Forms.Clipboard].Assembly.Location,
    [Windows.Forms.IDataObject].Assembly.Location
) + @((Get-ChildItem (Split-Path ([Windows.Forms.Clipboard].Assembly.Location)) -Filter 'System.Private.Windows*.dll').FullName)
Add-Type -ReferencedAssemblies ($pasteReferences | Group-Object { [IO.Path]::GetFileName($_) } | ForEach-Object { $_.Group[0] }) @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class VerifyPasteImage {
    delegate bool EnumWindow(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback, IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, System.Text.StringBuilder name, int capacity);
    public static IntPtr[] Dialogs(int pid) {
        var dialogs = new System.Collections.Generic.List<IntPtr>();
        EnumWindows((window, data) => {
            uint owner; GetWindowThreadProcessId(window, out owner);
            var name = new System.Text.StringBuilder(256); GetClassName(window, name, name.Capacity);
            if (owner == pid && IsWindowVisible(window) && name.ToString() == "#32770") dialogs.Add(window);
            return true;
        }, IntPtr.Zero);
        return dialogs.ToArray();
    }
    public static string[] Put(int width, int height, string mode) {
        byte[] pixels = new byte[width * height * 4];
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int offset = (y * width + x) * 4;
                pixels[offset] = (byte)(y < height / 2 ? 48 : 192);
                pixels[offset + 1] = 96;
                pixels[offset + 2] = (byte)(x < width / 2 ? 224 : 64);
                pixels[offset + 3] = (byte)(mode == "dib24" || mode == "bitmap" || mode == "rgb32" ? 255 : 128);
            }
        }
        using (Bitmap image = new Bitmap(width, height, PixelFormat.Format32bppArgb)) {
            BitmapData bits = image.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            try { Marshal.Copy(pixels, 0, bits.Scan0, pixels.Length); }
            finally { image.UnlockBits(bits); }
            using (MemoryStream png = new MemoryStream())
            using (MemoryStream dib = new MemoryStream()) {
                image.Save(png, ImageFormat.Png);
                png.Position = 0;
                bool legacy = mode == "dib24" || mode == "rgb32";
                bool bottomUp = mode == "both" || mode == "dib24";
                int header = legacy ? 40 : 124;
                int bpp = mode == "dib24" ? 24 : 32;
                int stride = ((width * bpp + 31) / 32) * 4;
                using (BinaryWriter writer = new BinaryWriter(dib, System.Text.Encoding.UTF8, true)) {
                    writer.Write(header);
                    writer.Write(width);
                    writer.Write(bottomUp ? height : -height);
                    writer.Write((ushort)1);
                    writer.Write((ushort)bpp);
                    writer.Write(legacy ? 0 : 3);
                    writer.Write(stride * height);
                    writer.Write(new byte[16]);
                    if (!legacy) {
                        writer.Write(0x00ff0000u);
                        writer.Write(0x0000ff00u);
                        writer.Write(0x000000ffu);
                        writer.Write(0xff000000u);
                        writer.Write(0x73524742u);
                        writer.Write(new byte[64]);
                    }
                    for (int row = 0; row < height; row++) {
                        int y = bottomUp ? height - 1 - row : row;
                        if (bpp == 32) { writer.Write(pixels, y * width * 4, width * 4); }
                        else {
                            for (int x = 0; x < width; x++) { writer.Write(pixels, (y * width + x) * 4, 3); }
                            writer.Write(new byte[stride - width * 3]);
                        }
                    }
                }
                dib.Position = 0;
                DataObject data = new DataObject();
                if (mode == "both" || mode == "v5") { data.SetData(DataFormats.GetFormat(17).Name, false, dib); }
                if (mode == "both" || mode == "png") { data.SetData("PNG", false, png); }
                if (legacy) { data.SetData(DataFormats.Dib, false, dib); }
                if (mode == "bitmap") { data.SetData(DataFormats.Bitmap, false, image); }
                Clipboard.SetDataObject(data, true);
                IDataObject observed = Clipboard.GetDataObject();
                if ((mode == "both" || mode == "v5") && !observed.GetDataPresent(DataFormats.GetFormat(17).Name, false)) {
                    throw new Exception("paste-image: CF_DIBV5 missing from clipboard");
                }
                if ((mode == "both" || mode == "png") && !observed.GetDataPresent("PNG", false)) {
                    throw new Exception("paste-image: PNG missing from clipboard");
                }
                return observed.GetFormats(false);
            }
        }
    }
    public static void Fixture(string path) {
        using (Bitmap image = new Bitmap(80, 60)) {
            using (Graphics graphics = Graphics.FromImage(image)) { graphics.Clear(Color.FromArgb(32, 180, 220)); }
            image.Save(path, ImageFormat.Png);
        }
    }
    public static int[] Preview(string path, int left, int top, int right, int bottom, bool second) {
        using (Bitmap image = new Bitmap(path)) {
            int minX = right, minY = bottom, maxX = -1, maxY = -1, count = 0;
            for (int y = Math.Max(0, top); y < Math.Min(bottom, image.Height); y++) {
                for (int x = Math.Max(0, left); x < Math.Min(right, image.Width); x++) {
                    Color c = image.GetPixel(x, y);
                    bool match = second ? c.R == 32 && c.G == 180 && c.B == 220 :
                        (c.R == 224 || c.R == 64) && c.G == 96 && (c.B == 48 || c.B == 192);
                    if (match) { minX = Math.Min(minX, x); minY = Math.Min(minY, y); maxX = Math.Max(maxX, x); maxY = Math.Max(maxY, y); count++; }
                }
            }
            if (count < 100 || maxX - minX < 16 || maxY - minY < 16) throw new Exception("paste-image: missing visible preview");
            return new int[] { minX, minY, maxX + 1, maxY + 1, count };
        }
    }
    public static int[] Decode(string path) {
        using (Bitmap image = new Bitmap(path)) {
            Color first = image.GetPixel(0, 0);
            Color last = image.GetPixel(image.Width - 1, image.Height - 1);
            return new int[] { image.Width, image.Height, first.R, first.G, first.B, first.A, last.R, last.G, last.B, last.A };
        }
    }
}
'@

function Invoke-PasteImageJourney($Session) {
    $cases = @()
    foreach ($provider in @('whatsapp', 'slack', 'signal', 'telegram')) {
        foreach ($size in @(@(1920, 1032), @(3840, 2160))) {
            $cases += @{ provider = $provider; width = $size[0]; height = $size[1]; mode = 'both' }
        }
    }
    foreach ($mode in @('v5', 'png', 'dib24', 'rgb32', 'bitmap')) {
        $cases += @{ provider = 'whatsapp'; width = 1920; height = 1032; mode = $mode }
    }
    $sizes = @()
    '[]' | Set-Content (Join-Path $Session.evidence 'sizes.json')
    $index = 0
    foreach ($case in $cases) {
        $index++
        $name = "paste-$index"
        $chat = "paste:$($case.provider)"
        Invoke-PaletteCommand $Session "Verification Paste $($case.provider)"
        $null = Wait-Until { (Read-Control $Session status).selected.id -eq $chat } "paste-image: $chat selected"
        Invoke-PaletteCommand $Session 'Compose message'
        $formats = [VerifyPasteImage]::Put($case.width, $case.height, $case.mode)
        Add-Content (Join-Path $Session.evidence 'actions.log') "clipboard: $name $($case.mode) $($case.width)x$($case.height)"
        Send-Keys $Session '^v'
        Save-Screen $Session "$name-staged"
        Send-Keys $Session '{ENTER}'
        $null = Wait-Until {
            $sends = @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.accepted })
            $sends.Count -eq $index -and (Read-Control $Session status).pending_sends -eq 0
        } "paste-image: $name image received exactly once"
        $sends = @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.accepted })
        $send = $sends[$index - 1]
        Assert-That ($send.multipart -and $send.body.chat -eq $chat) "paste-image: $name wrong upload type or chat"
        $upload = Join-Path $Session.evidence $send.upload
        $decoded = [VerifyPasteImage]::Decode($upload)
        Assert-That ($decoded[0] -eq $case.width -and $decoded[1] -eq $case.height) "paste-image: $name decoded dimensions changed"
        $alpha = if ($case.mode -in @('dib24', 'rgb32', 'bitmap')) { 255 } else { 128 }
        Assert-That (($decoded[2..9] -join ',') -eq "224,96,48,$alpha,64,96,192,$alpha") "paste-image: $name alpha, channels or row orientation changed"
        $sizes += @{ case = $index; provider = $case.provider; mode = $case.mode; width = $case.width; height = $case.height; raw_bytes = $case.width * $case.height * 4; formats = $formats; decoded = $decoded; upload = $send.upload; file_size = (Get-Item $upload).Length; sha256 = (Get-FileHash $upload).Hash.ToLowerInvariant(); client_id = $send.body.client_id }
        $sizes | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Session.evidence 'sizes.json')
        $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object { $_.id -eq $send.message_id -and $_.from_me -and $_.media_type -eq 'image' }).Count -eq 1 } "paste-image: $name acknowledged image visible"
        Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$name.messages.json")
        Save-Screen $Session "$name-sent"
        Hub-Pass $Session $name
    }
    Assert-That (@(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' }).Count -eq $cases.Count) 'paste-image: duplicate or failed send attempts'
    Invoke-MultiImageJourney $Session $index
    [Windows.Forms.Clipboard]::Clear()
    Save-Screen $Session after
}

function Get-PickerDialog($Session, [IntPtr]$Expected = [IntPtr]::Zero) {
    $open = $null
    foreach ($handle in [VerifyPasteImage]::Dialogs($Session.pid)) {
        $window = [Windows.Automation.AutomationElement]::FromHandle($handle)
        $filename = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, '1148'))
        if ($window.Current.Name -cne 'Open' -or $null -eq $filename -or ($filename.Current.ControlType -ne [Windows.Automation.ControlType]::ComboBox -and $filename.Current.ClassName -ne 'ComboBoxEx32') -or ($Expected -ne [IntPtr]::Zero -and $handle -ne $Expected) -or $null -ne $open) {
            $elements = $window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
            $text = (@($window.Current.Name) + @($elements | ForEach-Object { $_.Current.Name } | Where-Object { $_ })) -join ' | '
            throw "paste-image: unexpected #32770 dialog: $text"
        }
        $open = $window
    }
    return $open
}

function Add-PickerImage($Session, [string]$Path) {
    Click-Control $Session '1136'
    try {
        $window = Wait-Until { Get-PickerDialog $Session } 'paste-image: Open file dialog'
        $dialog = [IntPtr]$window.Current.NativeWindowHandle
        $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit)
        $filenameCondition = [Windows.Automation.AndCondition]::new(
            [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, '1148'),
            [Windows.Automation.OrCondition]::new(
                [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::ComboBox),
                [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'ComboBoxEx32')
            )
        )
        $edit = Wait-Until {
            $null = Get-PickerDialog $Session $dialog
            $filename = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $filenameCondition)
            if ($null -eq $filename) { return $false }
            $edits = $filename.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
            foreach ($candidate in $edits) {
                if ($candidate.Current.IsEnabled -and -not $candidate.Current.IsOffscreen -and $candidate.Current.IsKeyboardFocusable) {
                    $labels = @($filename.Current.Name, $candidate.Current.Name)
                    foreach ($control in @($filename, $candidate)) {
                        if ($null -ne $control.Current.LabeledBy) { $labels += $control.Current.LabeledBy.Current.Name }
                    }
                    if (@($labels | Where-Object { $_ }).Count -gt 0) {
                        Assert-That ($labels -ccontains 'File name:') 'paste-image: control 1148 is not labelled File name:'
                    }
                    return $candidate
                }
            }
        } 'paste-image: file-dialog editable filename'
        $edit.SetFocus()
        foreach ($keys in @('^a', $Path, '{ENTER}')) {
            $null = Get-PickerDialog $Session $dialog
            Assert-That ([Windows.Automation.Automation]::Compare([Windows.Automation.AutomationElement]::FocusedElement, $edit)) 'paste-image: File name edit does not have keyboard focus'
            Send-Keys $Session $keys
        }
        $null = Wait-Until { $null -eq (Get-PickerDialog $Session $dialog) } 'paste-image: file dialog closed'
    } catch {
        $failure = $_
        foreach ($handle in [VerifyPasteImage]::Dialogs($Session.pid)) {
            try {
                $popup = [Windows.Automation.AutomationElement]::FromHandle($handle)
                $elements = $popup.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
                $tree = @("$($popup.Current.ClassName) | $($popup.Current.Name)")
                foreach ($element in $elements) {
                    $tree += "$($element.Current.AutomationId) | $($element.Current.ClassName) | $($element.Current.ControlType.ProgrammaticName) | $($element.Current.Name) | focused=$($element.Current.HasKeyboardFocus)"
                }
                $tree | Set-Content (Join-Path $Session.evidence "picker-dialog-$($handle.ToInt64()).uia.txt")
            } catch {
                $_ | Out-String | Add-Content (Join-Path $Session.evidence 'picker-diagnostics.txt')
            }
        }
        throw $failure
    }
    Add-Content (Join-Path $Session.evidence 'actions.log') 'picker: UIA filename, keyboard path and Enter'
}

function Read-ImagePreviews($Session, [string]$Name) {
    Save-Screen $Session $Name
    $canvas = (Get-Edit (Get-Window $Session) '1024').Current.BoundingRectangle
    $compose = (Get-Edit (Get-Window $Session) '1032').Current.BoundingRectangle
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $path = Join-Path $Session.evidence "$Name.png"
    $first = [VerifyPasteImage]::Preview($path, [int]($canvas.Left - $screen.Left), [int]($canvas.Bottom - $screen.Top), [int]($canvas.Right - $screen.Left), [int]($compose.Top - $screen.Top), $false)
    $second = [VerifyPasteImage]::Preview($path, [int]($canvas.Left - $screen.Left), [int]($canvas.Bottom - $screen.Top), [int]($canvas.Right - $screen.Left), [int]($compose.Top - $screen.Top), $true)
    Assert-That ($first[2] -lt $second[0]) 'paste-image: two separate previews in attachment order'
    return @{ first = $first; second = $second }
}

function Invoke-MultiImageJourney($Session, [int]$Count) {
    $fixture = Join-Path (Join-Path $Session.root 'profile') 'second-image.png'
    [VerifyPasteImage]::Fixture($fixture)
    $multi = @()
    $removed = @()
    foreach ($provider in @('whatsapp', 'slack')) {
        New-Item (Join-Path $Session.evidence $provider) -ItemType Directory -Force | Out-Null
        Invoke-PaletteCommand $Session "Verification Paste $provider"
        $null = Wait-Until { (Read-Control $Session status).selected.id -eq "paste:$provider" } "paste-image: multi $provider selected"
        Invoke-PaletteCommand $Session 'Compose message'
        Save-Screen $Session "$provider/multi-before"
        $null = [VerifyPasteImage]::Put(80, 60, 'bitmap')
        Send-Keys $Session '^v'
        Add-PickerImage $Session $fixture
        $previews = Read-ImagePreviews $Session "$provider/multi-staged"
        Send-Keys $Session 'two-image-caption'
        Send-Keys $Session '{ENTER}'
        $null = Wait-Until {
            @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' }).Count -eq ($Count + 2) -and (Read-Control $Session status).pending_sends -eq 0
        } "paste-image: $provider two ordered image sends"
        $sends = @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' } | Select-Object -Skip $Count)
        Assert-That ($sends.Count -eq 2 -and $sends[0].body.text -ceq 'two-image-caption' -and $sends[1].body.text -ceq '') 'paste-image: caption belongs to first image only'
        foreach ($send in $sends) { Assert-That ($send.accepted -and $send.multipart -and $send.body.chat -eq "paste:$provider") 'paste-image: multi image routed once' }
        $first = [VerifyPasteImage]::Decode((Join-Path $Session.evidence $sends[0].upload))
        $second = [VerifyPasteImage]::Decode((Join-Path $Session.evidence $sends[1].upload))
        Assert-That (($first -join ',') -eq '80,60,224,96,48,255,64,96,192,255') 'paste-image: pasted image first'
        Assert-That (($second -join ',') -eq '80,60,32,180,220,255,32,180,220,255') 'paste-image: picker image second'
        $multi += @{ provider = $provider; sends = $sends; previews = $previews; decoded = @($first, $second) }
        ConvertTo-Json -InputObject $multi -Depth 16 | Set-Content (Join-Path $Session.evidence 'multi-sent.json')
        $Count += 2
        Save-Screen $Session "$provider/multi-sent"
        Invoke-PaletteCommand $Session 'Compose message'
        $null = [VerifyPasteImage]::Put(80, 60, 'bitmap')
        Send-Keys $Session '^v'
        Add-PickerImage $Session $fixture
        $previews = Read-ImagePreviews $Session "$provider/remove-staged"
        $screen = [Windows.Forms.SystemInformation]::VirtualScreen
        $x = $screen.Left + $previews.first[2] - 6
        $y = $screen.Top + $previews.first[1] + 6
        [VerifyMenus]::Click($Session.pid, $x, $y, $false)
        Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: remove first preview $provider x=$x y=$y"
        Save-Screen $Session "$provider/remove-one"
        Send-Keys $Session '{ENTER}'
        $null = Wait-Until {
            @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' }).Count -eq ($Count + 1) -and (Read-Control $Session status).pending_sends -eq 0
        } "paste-image: $provider only second image after removal"
        $sends = @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' } | Select-Object -Skip $Count)
        Assert-That ($sends.Count -eq 1 -and $sends[0].accepted -and $sends[0].body.chat -eq "paste:$provider" -and $sends[0].body.text -ceq '') 'paste-image: remove sends exactly one image'
        Assert-That ($sends[0].file_sha256 -eq $multi[-1].sends[1].file_sha256) 'paste-image: removal kept second image bytes'
        $removed += @{ provider = $provider; sends = $sends; click = @($x, $y); previews = $previews }
        ConvertTo-Json -InputObject $removed -Depth 16 | Set-Content (Join-Path $Session.evidence 'remove.json')
        $Count++
        Save-Screen $Session "$provider/remove-sent"
        Hub-Pass $Session "$provider-multi-remove"
    }
    $sends = @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' })
    Assert-That ($sends.Count -eq $Count -and @($sends.body.client_id | Select-Object -Unique).Count -eq $Count) 'paste-image: distinct per-image client ids, no extra sends'
}
