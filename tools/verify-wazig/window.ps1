Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
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
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct StartupInfo {
        public int cb;
        public string reserved, desktop, title;
        public int x, y, xSize, ySize, xCountChars, yCountChars, fillAttribute, flags;
        public short showWindow, reserved2Size;
        public IntPtr reserved2, standardInput, standardOutput, standardError;
    }
    [StructLayout(LayoutKind.Sequential)] public struct ProcessInformation {
        public IntPtr Process, Thread;
        public int ProcessId, ThreadId;
    }
    [DllImport("kernel32.dll", EntryPoint = "CreateProcessW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateProcess(string application, StringBuilder commandLine, IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint creationFlags, IntPtr environment, string directory, ref StartupInfo startup, out ProcessInformation process);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
    public static int Launch(string application, string commandLine, string[] environment, bool showNormal) {
        string[] sorted = (string[])environment.Clone();
        Array.Sort(sorted, StringComparer.OrdinalIgnoreCase);
        IntPtr block = Marshal.StringToHGlobalUni(string.Join("\0", sorted) + "\0\0");
        try {
            StartupInfo startup = new StartupInfo();
            startup.cb = Marshal.SizeOf(typeof(StartupInfo));
            if (showNormal) {
                startup.flags = 1;
                startup.showWindow = 1;
            }
            ProcessInformation process;
            if (!CreateProcess(application, new StringBuilder(commandLine), IntPtr.Zero, IntPtr.Zero, false, 0x400, block, null, ref startup, out process)) {
                throw new InvalidOperationException("CreateProcessW failed: " + Marshal.GetLastWin32Error());
            }
            CloseHandle(process.Process);
            CloseHandle(process.Thread);
            return process.ProcessId;
        } finally {
            Marshal.FreeHGlobal(block);
        }
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

function Get-LaunchZoomCount($Session) {
    $log = Join-Path $Session.root 'local/Messages/launch-log.txt'
    if (-not (Test-Path $log)) { return 0 }
    return @(Get-Content $log | Where-Object { $_.EndsWith(' startup: window zoomed=true') }).Count
}

function Start-WindowProcess($Session, $Start, [string]$Method) {
    $showNormal = $Method -eq 'createprocess-shownormal'
    $arguments = if ($showNormal) { '--verify-fixture' } else { '--verify-fixture --update-relaunch' }
    $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $environment = [string[]]@($Start.Environment.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" })
    $processId = [VerifyWindowJourney]::Launch($Session.exe, "`"$($Session.exe)`" $arguments", $environment, $showNormal)
    $app = Get-Process -Id $processId
    $Session.pid = $app.Id
    $Session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    $null = Wait-Until {
        $app.Refresh()
        if ($app.HasExited) { throw "App exited before $Method start" }
        $app.MainWindowHandle -ne [IntPtr]::Zero
    } "main window after $Method start"
    Invoke-Doctor $Session | Out-Null
    return $app
}

function Invoke-WindowJourney($Session, $Start, $App) {
    $steps = [Collections.Generic.List[object]]::new()
    $methods = @('process-start', 'process-start', 'process-start', 'createprocess-shownormal', 'createprocess-update-relaunch')
    $dotnetApp = $App
    try {
        foreach ($number in 1..5) {
            $method = $methods[$number - 1]
            $updateRelaunch = $number -in @(3, 5)
            $before = 0
            if ($number -gt 1) {
                $before = Get-LaunchZoomCount $Session
                if ($number -le 3) {
                    $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
                    if ($number -eq 3) { $Start.ArgumentList.Add('--update-relaunch') }
                    $App = [Diagnostics.Process]::Start($Start)
                    $dotnetApp = $App
                    $Session.pid = $App.Id
                    $Session.startTicks = $App.StartTime.ToUniversalTime().Ticks.ToString()
                    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
                    $null = Wait-Until {
                        $App.Refresh()
                        if ($App.HasExited) { throw "App exited before zoomed start $number" }
                        $App.MainWindowHandle -ne [IntPtr]::Zero
                    } "zoomed main window at start $number"
                    Invoke-Doctor $Session | Out-Null
                } else {
                    $App = Start-WindowProcess $Session $Start $method
                }
            }
            $state = Read-WindowPlacement $Session "start-$number" $updateRelaunch
            $state['start_method'] = $method
            $state['launch_zoomed_before'] = $before
            $steps.Add($state)
            Save-Screen $Session "start-$number"
            Assert-That $state.zoomed "Main window not zoomed at start $number ($method)"
            $state['launch_zoomed_after'] = Wait-Until {
                $count = Get-LaunchZoomCount $Session
                if ($count -gt $before) { $count }
            } "launch log line 'startup: window zoomed=true' after start $number ($method)"
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
            if ($number -lt 5) {
                Send-Keys $Session '%{F4}'
                Assert-That ($App.WaitForExit(20000)) "Zoomed journey app did not exit after Alt+F4 at start $number"
                if ($number -le 2) {
                    $App.StandardError.ReadToEnd() | Set-Content (Join-Path $Session.evidence "start-$number.stderr.log")
                }
            }
        }
        Save-Screen $Session after
        return $dotnetApp
    } finally {
        ConvertTo-Json -InputObject @($steps.ToArray()) -Depth 12 | Set-Content (Join-Path $Session.evidence 'window.json')
    }
}
