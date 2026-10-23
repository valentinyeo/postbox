Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class VerifyWindowJourney {
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Placement {
        public uint Length, Flags, ShowCommand;
        public Point MinPosition, MaxPosition;
        public Rect NormalPosition;
    }
    [StructLayout(LayoutKind.Sequential)] public struct MonitorInfo {
        public uint Size;
        public Rect Monitor, Work;
        public uint Flags;
    }
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr window);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr window, ref Placement placement);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW")] public static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
}
'@

function Read-WindowPlacement($Session, [string]$Step, [bool]$UpdateRelaunch = $false) {
    $window = Get-Window $Session
    $handle = [IntPtr]$window.Current.NativeWindowHandle
    $placement = [VerifyWindowJourney+Placement]::new()
    $placement.Length = [Runtime.InteropServices.Marshal]::SizeOf($placement)
    Assert-That ([VerifyWindowJourney]::GetWindowPlacement($handle, [ref]$placement)) "Cannot read zoomed placement: $Step"
    $monitor = [VerifyWindowJourney]::MonitorFromWindow($handle, 0)
    Assert-That ($monitor -ne [IntPtr]::Zero) "Cannot read zoomed monitor: $Step"
    $info = [VerifyWindowJourney+MonitorInfo]::new()
    $info.Size = [Runtime.InteropServices.Marshal]::SizeOf($info)
    Assert-That ([VerifyWindowJourney]::GetMonitorInfo($monitor, [ref]$info)) "Cannot read zoomed monitor rect: $Step"
    return [ordered]@{
        step = $Step; zoomed = [VerifyWindowJourney]::IsZoomed($handle)
        pid = $Session.pid; start_ticks = $Session.startTicks; hwnd = $handle.ToInt64()
        monitor_handle = $monitor.ToInt64(); monitor_rect = $info.Monitor; work_rect = $info.Work
        normal_rect = $placement.NormalPosition; root = $Session.root; id = $Session.id
        update_relaunch = $UpdateRelaunch
    }
}

function Invoke-WindowJourney($Session, $Start, $App) {
    $steps = [Collections.Generic.List[object]]::new()
    try {
        foreach ($number in 1..3) {
            if ($number -gt 1) {
                $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
                if ($number -eq 3) { $Start.ArgumentList.Add('--update-relaunch') }
                $App = [Diagnostics.Process]::Start($Start)
                $Session.pid = $App.Id
                $Session.startTicks = $App.StartTime.ToUniversalTime().Ticks.ToString()
                $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
                $null = Wait-Until {
                    $App.Refresh()
                    if ($App.HasExited) { throw "App exited before zoomed start $number" }
                    $App.MainWindowHandle -ne [IntPtr]::Zero
                } "zoomed main window at start $number"
                Invoke-Doctor $Session | Out-Null
            }
            $state = Read-WindowPlacement $Session "start-$number" ($number -eq 3)
            $steps.Add($state)
            Save-Screen $Session "start-$number"
            Assert-That $state.zoomed "Main window not zoomed at start $number"
            if ($number -gt 1) {
                Assert-That ($state.monitor_handle -eq $steps[1].monitor_handle) "Zoomed start $number moved to another monitor"
                Assert-That (($state.normal_rect | ConvertTo-Json -Compress) -eq ($steps[1].normal_rect | ConvertTo-Json -Compress)) "Zoomed start $number lost the saved normal rect"
            }
            if ($number -eq 1) {
                Send-Keys $Session '% '
                Send-Keys $Session 'r'
                $null = Wait-Until { -not [VerifyWindowJourney]::IsZoomed($App.MainWindowHandle) } 'zoomed false after keyboard restore'
                Send-Keys $Session '% '
                Send-Keys $Session 's'
                Send-Keys $Session '{RIGHT}{LEFT 20}{ENTER}'
                Send-Keys $Session '% '
                Send-Keys $Session 's'
                Send-Keys $Session '{DOWN}{UP 15}{ENTER}'
                $restored = Read-WindowPlacement $Session 'restored'
                $steps.Add($restored)
                Assert-That (-not $restored.zoomed) 'Restored main window still zoomed'
                $rect = $restored.normal_rect
                Assert-That ($rect.Right - $rect.Left -lt $state.normal_rect.Right - $state.normal_rect.Left -and $rect.Bottom - $rect.Top -lt $state.normal_rect.Bottom - $state.normal_rect.Top) 'Keyboard resize did not shrink the non-zoomed normal rect'
                Save-Screen $Session restored
            }
            if ($number -lt 3) {
                Send-Keys $Session '%{F4}'
                Assert-That ($App.WaitForExit(20000)) "Zoomed journey app did not exit after Alt+F4 at start $number"
                $App.StandardError.ReadToEnd() | Set-Content (Join-Path $Session.evidence "start-$number.stderr.log")
            }
        }
        Save-Screen $Session after
        return $App
    } finally {
        ConvertTo-Json -InputObject @($steps.ToArray()) -Depth 12 | Set-Content (Join-Path $Session.evidence 'window.json')
    }
}
