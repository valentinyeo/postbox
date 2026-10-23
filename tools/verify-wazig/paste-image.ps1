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
    [Windows.Forms.Clipboard]::Clear()
    Save-Screen $Session after
}
