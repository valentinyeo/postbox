Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class VerifyMentionPopup {
    delegate bool EnumWindow(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback, IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    public static double[] Frame(int pid) {
        double[] frame = null;
        EnumWindows((window, data) => {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner != pid || !IsWindowVisible(window)) return true;
            var name = new StringBuilder(256);
            GetClassName(window, name, name.Capacity);
            if (name.ToString() != "MessagesShortcodePopup") return true;
            Rect rect;
            if (!GetWindowRect(window, out rect)) return true;
            frame = new double[] { 1, rect.Right - rect.Left, rect.Bottom - rect.Top };
            return false;
        }, IntPtr.Zero);
        return frame ?? new double[] { 0, 0, 0 };
    }
}
'@

Send-Keys $session '%2'
$null = Wait-Until { (Read-Control $session status).view -eq 'slack' } 'Slack sidebar'
Send-Keys $session '^{TAB}'
$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.chat.id -eq 'slack:fixture-mentions:channel' -and $shown.chat.provider -eq 'slack' -and
        $shown.messages.Count -eq 5 -and @($shown.messages | Where-Object { $_.bubble[2] -le $_.bubble[0] -or $_.bubble[3] -le $_.bubble[1] }).Count -eq 0
} 'Slack mention messages painted'
Save-Screen $session before
$shown = Read-Control $session messages
$shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'before.messages.json')
Save-Screen $session after
$shown = Read-Control $session messages
$shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'after.messages.json')
$rows = @{}
foreach ($row in $shown.messages) { $rows[$row.id] = $row }
Assert-That ($rows.Count -eq 5) 'Slack mention fixture rows changed'
Assert-That ($rows['MENTION-NAMED'].text -ceq '@Fixture Peer hello') 'Cached sender name was not used for the known mention'
Assert-That ($rows['MENTION-NAMED'].text -ceq "@$($rows['MENTION-NAMED'].sender) hello") 'Mention name disagrees with the sender line'
Assert-That ($rows['MENTION-UNKNOWN'].text -ceq '@someone joins later') 'Unknown Slack member must show @someone'
Assert-That ($rows['MENTION-LABELLED'].text -ceq '@Outside Guest thanks report') 'Labelled Slack mention or report link label changed'
Assert-That (($rows['MENTION-LABELLED'].links -join ',') -ceq 'https://example.org/report') 'Report link target changed'
Assert-That ($rows['MENTION-GUEST'].text -ceq '@Guest Person joins @Fixture Peer') 'Guest missing from the member list did not resolve'
Assert-That ($rows['MENTION-GUEST'].sender -ceq 'Guest Person') 'Guest mention disagrees with the sender line'
Assert-That ($rows['MENTION-CONNECT'].text -ceq '@Guest Person meets @Connect Person') 'Slack Connect name or upstream-resolved guest changed'
foreach ($stage in @('before', 'after')) {
    $snapshot = Get-Content (Join-Path $Evidence "$stage.messages.json") -Raw | ConvertFrom-Json
    $rendered = $snapshot
    foreach ($row in $rendered.messages) { $row.PSObject.Properties.Remove('sender_id') }
    $rendered | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence "$stage.rendered.json")
    $snapshotText = $rendered | ConvertTo-Json -Depth 12
    $uiaText = Get-Content (Join-Path $Evidence "$stage.uia.txt") -Raw
    Assert-That ($snapshotText -cnotmatch '<@|<https://') 'Raw Slack mention or link markup reached the rendered snapshot'
    Assert-That ($uiaText -cnotmatch '<@') 'Raw Slack mention markup reached UI Automation'
    foreach ($fixtureId in @('U4A59H6UT', 'UUNKNOWN99', 'UHIDDEN01', 'UEXT00001', 'WCONNECT01')) {
        Assert-That ($snapshotText -cnotmatch [regex]::Escape($fixtureId)) "Fixture Slack id $fixtureId reached the rendered snapshot"
        Assert-That ($uiaText -cnotmatch [regex]::Escape($fixtureId)) "Fixture Slack id $fixtureId reached UI Automation"
    }
}
function Save-MentionFrame($Session, [string]$Name) {
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
}

Invoke-PaletteCommand $session 'Compose message'
Send-Keys $session '@fix'
$null = Wait-Until { ([VerifyMentionPopup]::Frame([int]$session.pid))[0] -eq 1 } 'Slack mention suggestions'
$frame = [VerifyMentionPopup]::Frame([int]$session.pid)
$shown = ($frame[0] -eq 1)
Assert-That ($shown -and $frame[1] -gt 0 -and $frame[2] -gt 0 -and $frame[2] -lt $frame[1]) 'Mention suggestion list has no usable size'
$width = [int]$frame[1]
$height = [int]$frame[2]
@{ visible = $shown; width = $width; height = $height } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'mention-suggestions.json')
Save-MentionFrame $session mention-suggestions
Send-Keys $session '{ENTER}'
$null = Wait-Until { (Read-Edit $compose) -ceq '<@U4A59H6UT>' } 'Slack mention picked'
$after = [VerifyMentionPopup]::Frame([int]$session.pid)
$still_open = ($after[0] -eq 1)
@{ composer = (Read-Edit $compose); popup = $still_open } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'mention-picked.json')
Save-Screen $session mention-picked
Send-Keys $session ' hello'
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    (Read-Control $session status).pending_sends -eq 0 -and
        @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.chat -ceq 'slack:fixture-mentions:channel' -and $_.body.text -ceq '<@U4A59H6UT> hello' -and $_.status -eq 200 }).Count -eq 1
} 'Slack mention send'
Invoke-PaletteCommand $session 'Refresh'
$null = Wait-Until {
    $history = Read-Control $session messages
    $sent = @($history.messages | Where-Object { $_.id -ceq 'MENTION-SENT' -and $_.from_me -and $_.text -ceq '@Fixture Peer hello' -and $_.bubble[2] -gt $_.bubble[0] })
    $history.chat.id -ceq 'slack:fixture-mentions:channel' -and $sent.Count -eq 1 -and $history.messages.Count -eq 6 -and @($history.messages | Where-Object { $_.from_me }).Count -eq 1 -and @($history.messages | Where-Object { $_.text -cmatch '<@' }).Count -eq 0
} 'Slack mention acknowledged bubble renders the name without raw tokens'
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'mention-sent.messages.json')
Save-Screen $session mention-sent
Hub-Pass $session mention-compose
Hub-Pass $session mention-display
