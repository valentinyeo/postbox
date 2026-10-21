$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class VerifyWindow {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)]
    public static extern IntPtr ReadText(IntPtr window, uint message, UIntPtr capacity, StringBuilder text, uint flags, uint timeout, out UIntPtr length);
}
'@

function Assert-That($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Wait-Until([scriptblock]$Check, [string]$Description) {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $value = & $Check
        if ($value) { return $value }
        [System.Threading.Thread]::Sleep(100)
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out: $Description"
}

function Read-Session([string]$Evidence) {
    Get-Content (Join-Path $Evidence 'session.json') -Raw | ConvertFrom-Json
}

function Get-App($Session) {
    $app = Get-Process -Id $Session.pid -ErrorAction Stop
    Assert-That ($app.StartTime.ToUniversalTime().Ticks.ToString() -eq $Session.startTicks) 'PID was reused'
    Assert-That ($app.Path -eq $Session.exe) 'Wrong executable path'
    Assert-That ((Get-FileHash $app.Path).Hash -eq $Session.sha256) 'Executable changed after launch'
    return $app
}

function Read-Control($Session, [string]$Command) {
    $start = [Diagnostics.ProcessStartInfo]::new($Session.ctl)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.ArgumentList.Add($Command)
    $start.Environment['USERNAME'] = $Session.username
    $child = [Diagnostics.Process]::Start($start)
    $text = $child.StandardOutput.ReadToEnd()
    $errors = $child.StandardError.ReadToEnd()
    Assert-That ($child.WaitForExit(15000)) 'Read-only control client timed out'
    Assert-That ($child.ExitCode -eq 0) "Read-only control failed: $errors"
    $response = $text | ConvertFrom-Json
    Assert-That $response.ok 'Control response is not OK'
    return $response.result
}

function Get-Window($Session) {
    $app = Get-App $Session
    $app.Refresh()
    Assert-That ($app.MainWindowHandle -ne [IntPtr]::Zero) 'App window is not up'
    $window = [Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    Assert-That ($window.Current.ProcessId -eq $Session.pid) 'UI Automation found another process'
    Assert-That ($window.Current.ClassName -eq 'MessagesZig') 'Wrong window class'
    Assert-That ($window.Current.Name -eq 'Wazig Messages v0.0.526') 'Wrong build title'
    return $window
}

function Get-Edit($Window, [string]$Id) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    $edit = $Window.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
    Assert-That ($null -ne $edit) "Missing stable edit AutomationId=$Id"
    return $edit
}

function Read-Edit($Edit) {
    $handle = [IntPtr]$Edit.Current.NativeWindowHandle
    Assert-That ($handle -ne [IntPtr]::Zero -and $Edit.Current.ClassName -eq 'Edit') 'Expected a native edit control'
    $text = [Text.StringBuilder]::new(65537)
    $length = [UIntPtr]::Zero
    $ok = [VerifyWindow]::ReadText($handle, 13, [UIntPtr]65537, $text, 2, 2000, [ref]$length)
    Assert-That ($ok -ne [IntPtr]::Zero) 'Read-only WM_GETTEXT timed out'
    return $text.ToString()
}

function Send-Keys($Session, [string]$Keys) {
    $app = Get-App $Session
    $foreground = [Windows.Automation.AutomationElement]::FromHandle([VerifyWindow]::GetForegroundWindow())
    if ($foreground.Current.ProcessId -ne $Session.pid) {
        [VerifyWindow]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
        $foreground = [Windows.Automation.AutomationElement]::FromHandle([VerifyWindow]::GetForegroundWindow())
    }
    Assert-That ($foreground.Current.ProcessId -eq $Session.pid) 'Refusing keyboard input to another app'
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Add-Content (Join-Path $Session.evidence 'actions.log') "keys: $Keys"
}

function Save-Screen($Session, [string]$Name) {
    $window = Get-Window $Session
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $image = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($image)
    try {
        $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
        $image.Save((Join-Path $Session.evidence "$Name.png"), [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $image.Dispose()
    }
    $elements = $window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
    $tree = @("$($window.Current.ClassName) | $($window.Current.Name)")
    foreach ($element in $elements) {
        $tree += "$($element.Current.AutomationId) | $($element.Current.ClassName) | $($element.Current.Name)"
    }
    $tree | Set-Content (Join-Path $Session.evidence "$Name.uia.txt")
    Read-Control $Session status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.state.json")
}

function Invoke-Doctor($Session) {
    $window = Get-Window $Session
    $search = Get-Edit $window '1008'
    $compose = Get-Edit $window '1032'
    Assert-That $compose.Current.IsEnabled 'Fixture chat is not usable'
    $null = Read-Edit $search
    $status = Read-Control $Session status
    Assert-That ($status.version -eq '0.0.526') 'Wrong control build'
    Assert-That ($status.sync -eq 'stopped' -and -not $status.slack_connected) 'Provider unexpectedly connected'
    Assert-That ($status.pending_sends -eq 0 -and $status.pending_archives -eq 0) 'Unexpected pending writes'
    $status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'doctor.json')
    Write-Output 'DOCTOR PASSED: build, owned window, usable fixture and readable UI Automation edits'
}
