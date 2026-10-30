Add-Type -Path "$PSScriptRoot/menus.cs"

$caretReferences = @((Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll').FullName) + @(
    [Drawing.Bitmap].Assembly.Location,
    [Drawing.Color].Assembly.Location
)
Add-Type -ReferencedAssemblies ($caretReferences | Group-Object { [IO.Path]::GetFileName($_) } | ForEach-Object { $_.Group[0] }) @'
using System;
using System.Runtime.InteropServices;
public static class VerifyCaret {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct ThreadInfo {
        public int Size, Flags;
        public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        public Rect CaretRect;
    }
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint thread, ref ThreadInfo info);
    [DllImport("user32.dll")] public static extern uint GetCaretBlinkTime();
    [StructLayout(LayoutKind.Sequential)] struct MouseInput { public int x, y; public uint data, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KeyboardInput { public ushort key, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion { [FieldOffset(0)] public MouseInput mouse; [FieldOffset(0)] public KeyboardInput keyboard; }
    [StructLayout(LayoutKind.Sequential)] struct Input { public uint type; public InputUnion data; }
    [DllImport("user32.dll")] static extern uint SendInput(uint count, Input[] input, int size);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    public static void TypeUnicode(int pid, string text) {
        uint owner;
        GetWindowThreadProcessId(GetForegroundWindow(), out owner);
        if (owner != pid) throw new Exception("Refusing keyboard input outside owned process");
        foreach (char unit in text) {
            var down = new Input { type = 1, data = new InputUnion { keyboard = new KeyboardInput { scan = unit, flags = 4 } } };
            var up = new Input { type = 1, data = new InputUnion { keyboard = new KeyboardInput { scan = unit, flags = 6 } } };
            if (SendInput(2, new Input[] { down, up }, Marshal.SizeOf(typeof(Input))) != 2) throw new Exception("Unicode SendInput failed");
        }
    }
    public static int[] FindWordGap(System.Drawing.Bitmap image, int top, int bottom, int fillMax) {
        int first = -1, last = -1;
        var occupied = new bool[image.Width];
        for (int x = 0; x < image.Width; x++) for (int y = top; y <= bottom; y++) {
            var p = image.GetPixel(x, y);
            if (Math.Max(p.R, Math.Max(p.G, p.B)) > fillMax + 40) { occupied[x] = true; first = first < 0 ? x : first; last = x; }
        }
        int bestStart = -1, bestEnd = -1;
        for (int x = first + 1; first >= 0 && x < last;) {
            if (occupied[x]) { x++; continue; }
            int start = x;
            while (x < last && !occupied[x]) x++;
            if (bestStart < 0 || x - start > bestEnd - bestStart) { bestStart = start; bestEnd = x; }
        }
        return new int[] { bestStart, bestEnd };
    }
    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, UIntPtr wparam, IntPtr lparam, uint flags, uint timeout, out UIntPtr result);
    public static int CountInk(System.Drawing.Bitmap image, int fillMax) {
        int count = 0;
        for (int y = 0; y < image.Height; y++) for (int x = 0; x < image.Width; x++) {
            var p = image.GetPixel(x, y);
            if (Math.Max(p.R, Math.Max(p.G, p.B)) > fillMax + 40) count++;
        }
        return count;
    }
    public static int[] Measure(System.Drawing.Bitmap off, System.Drawing.Bitmap on, int fillMax) {
        int left = off.Width, right = -1, top = off.Height, bottom = -1;
        for (int x = 0; x < off.Width; x++) {
            int changed = 0, y0 = off.Height, y1 = -1;
            for (int y = 0; y < off.Height; y++) {
                var a = off.GetPixel(x, y); var b = on.GetPixel(x, y);
                if (Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B) > 100) {
                    changed++; y0 = Math.Min(y0, y); y1 = Math.Max(y1, y);
                }
            }
            if (changed >= 5) { left = Math.Min(left, x); right = x; top = Math.Min(top, y0); bottom = Math.Max(bottom, y1); }
        }
        if (right < 0) return new int[] { -1, -1, -1, -1, -1 };
        int inkRight = -1;
        for (int y = top; y <= bottom; y++) for (int x = 0; x < off.Width; x++) {
            var p = off.GetPixel(x, y);
            if (Math.Max(p.R, Math.Max(p.G, p.B)) > fillMax + 40) inkRight = Math.Max(inkRight, x);
        }
        return new int[] { left, right, top, bottom, inkRight };
    }
}
'@

function Get-CaretOnOff([int[]]$Ink) {
    $low = ($Ink | Measure-Object -Minimum).Minimum
    $high = ($Ink | Measure-Object -Maximum).Maximum
    $spread = $high - $low
    $phases = @()
    if ($spread -ge 8) {
        foreach ($count in $Ink) {
            $state = if ($count - $low -ge $spread / 2) { 1 } else { 0 }
            if ($phases.Count -eq 0 -or $phases[-1] -ne $state) { $phases += $state }
        }
    }
    return @{ low = $low; high = $high; on = @($phases | Where-Object { $_ -eq 1 }).Count; off = @($phases | Where-Object { $_ -eq 0 }).Count; phases = $phases }
}

function Test-CaretOracle {
    $steady = Get-CaretOnOff @(40, 40, 40, 40, 40, 40)
    Assert-That ($steady.on -eq 0 -and $steady.off -eq 0) 'caret oracle counted phases in a steady frame series'
    $blinking = Get-CaretOnOff @(40, 40, 58, 58, 40, 40, 58, 58, 40, 58)
    Assert-That ($blinking.on -ge 2 -and $blinking.off -ge 2) 'caret oracle missed a blinking series'
}

function Measure-CaretTheme($Session, [string]$Theme) {
    Invoke-PaletteCommand $Session 'Compose message'
    $window = Get-Window $Session
    $edit = Get-Edit $window '1032'
    Send-Keys $Session 'abc'
    $null = Wait-Until { (Read-Edit $edit) -eq 'abc' } "caret $Theme typed text"
    [System.Threading.Thread]::Sleep(900)
    $handle = [IntPtr]$window.Current.NativeWindowHandle
    $processId = 0
    $thread = [VerifyWindow]::GetWindowThreadProcessId($handle, [ref]$processId)
    $info = [VerifyCaret+ThreadInfo]::new()
    $info.Size = [Runtime.InteropServices.Marshal]::SizeOf([type][VerifyCaret+ThreadInfo])
    $reading = [VerifyCaret]::GetGUIThreadInfo($thread, [ref]$info)
    $bounds = $edit.Current.BoundingRectangle
    $desktop = [Windows.Forms.SystemInformation]::VirtualScreen
    $left = [int]($bounds.Left - $desktop.Left)
    $top = [int]($bounds.Top - $desktop.Top)
    $width = [Math]::Min(260, [int]$bounds.Width)
    $height = [int]$bounds.Height
    $frames = @()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt 24; $i++) {
        $image = [Drawing.Bitmap]::new($width, $height)
        $graphics = [Drawing.Graphics]::FromImage($image)
        try {
            $graphics.CopyFromScreen($left + $desktop.Left, $top + $desktop.Top, 0, 0, [Drawing.Size]::new($width, $height))
        } finally { $graphics.Dispose() }
        $frames += @{ at = $clock.ElapsedMilliseconds; image = $image }
        [System.Threading.Thread]::Sleep(130)
    }
    $fill = $frames[0].image.GetPixel(2, 2)
    $fillMax = [Math]::Max($fill.R, [Math]::Max($fill.G, $fill.B))
    $ink = @()
    $stamps = @()
    foreach ($frame in $frames) {
        $count = 0
        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $pixel = $frame.image.GetPixel($x, $y)
                if ([Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B)) -gt $fillMax + 40) { $count++ }
            }
        }
        $ink += $count
        $stamps += $frame.at
    }
    $frames[0].image.Save((Join-Path $Session.evidence "caret-$Theme-first.png"), [Drawing.Imaging.ImageFormat]::Png)
    $best = 0
    for ($i = 1; $i -lt $ink.Count; $i++) { if ($ink[$i] -gt $ink[$best]) { $best = $i } }
    $frames[$best].image.Save((Join-Path $Session.evidence "caret-$Theme-brightest.png"), [Drawing.Imaging.ImageFormat]::Png)
    foreach ($frame in $frames) { $frame.image.Dispose() }
    $phases = Get-CaretOnOff $ink
    Save-Screen $Session "caret-$Theme"
    Send-Keys $Session '^a{BACKSPACE}'
    $null = Wait-Until { (Read-Edit $edit) -eq '' } "caret $Theme empty edit"
    $caretOwner = if ($info.Caret -eq [IntPtr]::Zero) { 'none' } elseif ($info.Caret -eq [IntPtr]$edit.Current.NativeWindowHandle) { 'composer' } else { 'other' }
    return [ordered]@{
        theme = $Theme; thread_reading = $reading; caret_owner = $caretOwner
        caret_rect = @{ left = $info.CaretRect.Left; top = $info.CaretRect.Top; right = $info.CaretRect.Right; bottom = $info.CaretRect.Bottom }
        focus_is_composer = ($info.Focus -eq [IntPtr]$edit.Current.NativeWindowHandle)
        blink_time_ms = [VerifyCaret]::GetCaretBlinkTime(); edit = @{ left = $bounds.Left; top = $bounds.Top; width = $bounds.Width; height = $bounds.Height }
        fill_max = $fillMax; ink_low = $phases.low; ink_high = $phases.high; on = $phases.on; off = $phases.off
        phases = $phases.phases; ink = $ink; frame_ms = $stamps
    }
}

function Measure-CaretAlignment($Session, $Edit, [string]$Name, [string]$Text, [bool]$Unicode = $false) {
    Send-Keys $Session '^a{BACKSPACE}'
    if ($Unicode) {
        [VerifyCaret]::TypeUnicode($Session.pid, $Text)
        Add-Content (Join-Path $Session.evidence 'actions.log') "Unicode SendInput: $Name"
    } else { Send-Keys $Session $Text }
    $null = Wait-Until { (Read-Edit $Edit) -ceq $Text } "$Name typed text"
    Assert-That $Edit.Current.HasKeyboardFocus "$Name edit is not focused"
    $bounds = $Edit.Current.BoundingRectangle
    $width = [int]$bounds.Width
    $height = [int]$bounds.Height
    Assert-That ($width -gt 2 -and $height -gt 2) "$Name edit bounds missing"
    $native = [UIntPtr]::Zero
    $ok = [VerifyCaret]::SendMessageTimeout([IntPtr]$Edit.Current.NativeWindowHandle, 0x00d6, [UIntPtr]$Text.Length, [IntPtr]::Zero, 2, 2000, [ref]$native)
    Assert-That ($ok -ne [IntPtr]::Zero) "$Name native end position unavailable"
    $packed = $native.ToUInt64()
    $nativeX = [int]($packed -band 0xffff)
    $nativeY = [int](($packed -shr 16) -band 0xffff)
    if ($nativeX -ge 32768) { $nativeX -= 65536 }
    if ($nativeY -ge 32768) { $nativeY -= 65536 }
    Save-Screen $Session "alignment-$Name"
    $frames = @()
    $ink = @()
    try {
        for ($i = 0; $i -lt 24; $i++) {
            $image = [Drawing.Bitmap]::new($width, $height)
            $graphics = [Drawing.Graphics]::FromImage($image)
            try { $graphics.CopyFromScreen([int]$bounds.Left, [int]$bounds.Top, 0, 0, [Drawing.Size]::new($width, $height)) }
            finally { $graphics.Dispose() }
            $frames += $image
            [System.Threading.Thread]::Sleep(130)
        }
        $fill = $frames[0].GetPixel(2, 2)
        $fillMax = [Math]::Max($fill.R, [Math]::Max($fill.G, $fill.B))
        foreach ($image in $frames) { $ink += [VerifyCaret]::CountInk($image, $fillMax) }
        $low = 0; $high = 0
        for ($i = 1; $i -lt $ink.Count; $i++) {
            if ($ink[$i] -lt $ink[$low]) { $low = $i }
            if ($ink[$i] -gt $ink[$high]) { $high = $i }
        }
        $frames[$low].Save((Join-Path $Session.evidence "alignment-$Name-off.png"), [Drawing.Imaging.ImageFormat]::Png)
        $frames[$high].Save((Join-Path $Session.evidence "alignment-$Name-on.png"), [Drawing.Imaging.ImageFormat]::Png)
        $pixels = [VerifyCaret]::Measure($frames[$low], $frames[$high], $fillMax)
        $phases = Get-CaretOnOff $ink
        return [ordered]@{
            name = $Name; text = $Text; control = $Edit.Current.AutomationId
            bounds = @{ left = $bounds.Left; top = $bounds.Top; width = $width; height = $height }
            native_end = @{ x = $nativeX; y = $nativeY }
            caret = @{ left = $pixels[0]; right = $pixels[1]; top = $pixels[2]; bottom = $pixels[3] }
            ink_right = $pixels[4]; gap = ($pixels[0] - $pixels[4] - 1)
            tolerance = 5; on = $phases.on; off = $phases.off; ink = $ink; fill_max = $fillMax
        }
    } finally { foreach ($image in $frames) { $image.Dispose() } }
}

function Invoke-CaretAlignment($Session) {
    $samples = @()
    $short = 'abc'
    $long = 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm'
    $emoji = [char]::ConvertFromUtf32(0x1f600)
    $zwj = [char]::ConvertFromUtf32(0x1f469) + [char]0x200d + [char]::ConvertFromUtf32(0x1f4bb)
    $clicks = @()
    foreach ($entry in @(
        @{ name = 'composer'; shortcut = ''; id = '1032' },
        @{ name = 'search'; shortcut = '^f'; id = '1064' },
        @{ name = 'palette'; shortcut = '^k'; id = '1064' }
    )) {
        if ($entry.shortcut) {
            Send-Keys $Session $entry.shortcut
            $edit = Get-Edit (Get-PaletteWindow $Session) $entry.id
        } else {
            Invoke-PaletteCommand $Session 'Compose message'
            $edit = Get-Edit (Get-Window $Session) $entry.id
        }
        foreach ($case in @(
            @{ name = 'short'; text = $short; unicode = $false },
            @{ name = 'long'; text = $long; unicode = $false },
            @{ name = 'kerning'; text = 'AVATAR office Wavy'; unicode = $false },
            @{ name = 'spaces'; text = 'MMMM        MMMM'; unicode = $false },
            @{ name = 'emoji'; text = "word $($emoji)x"; unicode = $true },
            @{ name = 'emoji-zwj'; text = "team $($zwj)x"; unicode = $true }
        )) {
            $samples += Measure-CaretAlignment $Session $edit "$($entry.name)-$($case.name)" $case.text $case.unicode
            $samples | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'alignment.json')
            if ($case.name -eq 'spaces') {
                $sample = $samples[-1]
                $image = [Drawing.Bitmap]::new((Join-Path $Session.evidence "alignment-$($entry.name)-spaces-off.png"))
                try {
                    $gap = if ($sample.caret.top -ge 0 -and $sample.caret.bottom -lt $image.Height) {
                        [VerifyCaret]::FindWordGap($image, $sample.caret.top, $sample.caret.bottom, $sample.fill_max)
                    } else { @(-1, -1) }
                } finally { $image.Dispose() }
                $click = [ordered]@{ name = $entry.name; gap_left = $gap[0]; gap_right = $gap[1]; measured = ($gap[0] -ge 0 -and $gap[1] - $gap[0] -ge 8) }
                if ($click.measured) {
                    $click.x = [int]$sample.bounds.left + [int](($gap[0] + $gap[1]) / 2)
                    $click.y = [int]$sample.bounds.top + [int](($sample.caret.top + $sample.caret.bottom) / 2)
                    [VerifyMenus]::Click($Session.pid, $click.x, $click.y, $false)
                    Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: $($entry.name) text gap x=$($click.x) y=$($click.y)"
                    Send-Keys $Session 'x'
                    $null = Wait-Until { (Read-Edit $edit).Contains('x') } "$($entry.name) click marker inserted"
                    $click.actual = Read-Edit $edit
                    $click.marker_index = $click.actual.IndexOf('x')
                    $click.correct = ($click.marker_index -ge 7 -and $click.marker_index -le 9 -and $click.actual.Replace('x', '') -ceq $case.text)
                    Save-Screen $Session "alignment-$($entry.name)-click"
                }
                $clicks += $click
                $clicks | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'alignment-clicks.json')
            }
        }
        Send-Keys $Session '^a{BACKSPACE}'
        if ($entry.shortcut) { Send-Keys $Session '{ESC}' }
    }
    foreach ($click in $clicks) {
        Assert-That ($click.measured -and $click.correct) "$($click.name): click marker missed the visual word gap"
    }
    foreach ($sample in $samples) {
        Assert-That ($sample.on -ge 2 -and $sample.off -ge 2 -and $sample.caret.left -ge 0 -and $sample.ink_right -ge 0) "$($sample.name): cannot measure caret and ink"
        Assert-That ($sample.gap -ge -2 -and $sample.gap -le $sample.tolerance) "$($sample.name): caret-to-ink gap $($sample.gap) pixels exceeds tolerance"
    }
}

function Invoke-CaretJourney($Session, $Start, $App) {
    Test-CaretOracle
    $themes = [ordered]@{}
    $themes['amoled'] = Measure-CaretTheme $Session 'amoled'
    Send-Keys $Session '^k'
    Send-Keys $Session 'Theme: Graphite'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { (Read-Control $Session status).theme -eq 'amoled' } 'graphite theme reapplied'
    $themes['reapplied'] = Measure-CaretTheme $Session 'reapplied'
    [ordered]@{ themes = $themes } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'caret.json')
    Save-Screen $Session after
    foreach ($name in $themes.Keys) {
        $theme = $themes[$name]
        Assert-That ($theme.on -ge 2 -and $theme.off -ge 2) "caret does not blink in $name composer: owner=$($theme.caret_owner) on=$($theme.on) off=$($theme.off) ink=$($theme.ink_low)..$($theme.ink_high)"
    }
    Invoke-CaretAlignment $Session
    return $App
}
