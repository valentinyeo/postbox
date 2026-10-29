Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AppIconNative {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll")] public static extern bool FreeLibrary(IntPtr module);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadImage(IntPtr module, IntPtr name, uint type, int x, int y, uint flags);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll", EntryPoint = "GetClassLongPtrW")] public static extern IntPtr GetClassLongPtr(IntPtr window, int index);
    [DllImport("user32.dll")] public static extern bool DrawIconEx(IntPtr dc, int x, int y, IntPtr icon, int width, int height, uint step, IntPtr brush, uint flags);
    [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll", EntryPoint = "SendMessageW")] public static extern IntPtr SendMessage(IntPtr window, uint message, UIntPtr wparam, IntPtr lparam);
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
}
'@
function Save-AppIcon([IntPtr]$Icon, [int]$Size, [string]$Name) {
    Assert-That ($Icon -ne [IntPtr]::Zero) "Missing native icon: $Name"
    $bitmap = [Drawing.Bitmap]::new($Size, $Size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([Drawing.Color]::Black)
        $dc = $graphics.GetHdc()
        try { Assert-That ([AppIconNative]::DrawIconEx($dc, 0, 0, $Icon, $Size, $Size, 0, [IntPtr]::Zero, 3)) 'DrawIconEx failed' }
        finally { $graphics.ReleaseHdc($dc) }
        $flag = $bitmap.GetPixel([int]($Size * 0.65), [int]($Size * 0.3))
        Assert-That ($flag.R -gt 210 -and $flag.G -gt 90 -and $flag.G -lt 170 -and $flag.B -lt $flag.G) "Approved red flag missing: $Name"
        $pole = $bitmap.GetPixel([int]($Size * 0.27), [int]($Size * 0.75))
        Assert-That ($pole.R -gt 140 -and $pole.R -lt 175 -and [Math]::Abs([int]$pole.R - $pole.G) -lt 5) "Flag pole missing: $Name"
        $bitmap.Save((Join-Path $session.evidence "$Name.png"), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
$app = Get-App $session
$module = [AppIconNative]::LoadLibraryEx($session.exe, [IntPtr]::Zero, 2)
Assert-That ($module -ne [IntPtr]::Zero) 'Cannot open shipped executable resources'
try {
    foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
        $icon = [AppIconNative]::LoadImage($module, [IntPtr]1, 1, $size, $size, 0)
        try { Save-AppIcon $icon $size "resource-$size" }
        finally { if ($icon -ne [IntPtr]::Zero) { $null = [AppIconNative]::DestroyIcon($icon) } }
    }
} finally { $null = [AppIconNative]::FreeLibrary($module) }
Save-AppIcon ([AppIconNative]::GetClassLongPtr($app.MainWindowHandle, -14)) 32 'window-big'
Save-AppIcon ([AppIconNative]::GetClassLongPtr($app.MainWindowHandle, -34)) 16 'window-small'
$null = [VerifyWindow]::ShowWindow($app.MainWindowHandle, 9)
$null = [VerifyWindow]::SetWindowPos($app.MainWindowHandle, [IntPtr]::Zero, 120, 80, 920, 680, 0x14)
$null = [VerifyWindow]::SetForegroundWindow($app.MainWindowHandle)
Save-Screen $session 'desktop-taskbar-100'
[AppIconNative]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
try {
    [AppIconNative]::keybd_event(0x09, 0, 0, [UIntPtr]::Zero)
    [AppIconNative]::keybd_event(0x09, 0, 2, [UIntPtr]::Zero)
    Save-Screen $session 'alt-tab'
} finally { [AppIconNative]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero) }
$rect = [AppIconNative+Rect]::new()
$rect.Left = 40; $rect.Top = 40; $rect.Right = 1200; $rect.Bottom = 860
$memory = [Runtime.InteropServices.Marshal]::AllocHGlobal([Runtime.InteropServices.Marshal]::SizeOf($rect))
try {
    [Runtime.InteropServices.Marshal]::StructureToPtr($rect, $memory, $false)
    $null = [AppIconNative]::SendMessage($app.MainWindowHandle, 0x02E0, [UIntPtr](144 -bor (144 -shl 16)), $memory)
    Save-Screen $session 'window-dpi-transition-150'
} finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($memory) }
@{
    executable_sha256 = (Get-FileHash $session.exe).Hash
    sizes = @(16, 24, 32, 48, 64, 128, 256)
    class_icons = @('big', 'small')
    host_dpi = [VerifyWindow]::GetDpiForWindow($app.MainWindowHandle)
    app_dpi_transition = 144
    dpi_method = 'WM_DPICHANGED; shell remains at host DPI, resource-24 proves 150% small icon'
} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $session.evidence 'icon-proof.json')
'APP_ICON_NATIVE_OK' | Set-Content (Join-Path $session.evidence 'icon-result.txt')
