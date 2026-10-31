Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DictationNative {
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] public struct HARDWAREINPUT { public uint message; public ushort low, high; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION {
        [FieldOffset(0)] public MOUSEINPUT mouse;
        [FieldOffset(0)] public KEYBDINPUT keyboard;
        [FieldOffset(0)] public HARDWAREINPUT hardware;
    }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION data; }
    [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll", EntryPoint="SendMessageTimeoutW", SetLastError=true)]
    public static extern IntPtr Selection(IntPtr window, uint message, ref uint start, ref uint end, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", EntryPoint="SendMessageTimeoutW", SetLastError=true)]
    public static extern IntPtr SetSelection(IntPtr window, uint message, UIntPtr start, IntPtr end, uint flags, uint timeout, out UIntPtr result);
    public static bool Key(ushort vk, bool up) {
        INPUT input = new INPUT { type = 1, data = new INPUTUNION { keyboard = new KEYBDINPUT { vk = vk, flags = up ? 2u : 0u } } };
        return SendInput(1, new INPUT[] { input }, Marshal.SizeOf<INPUT>()) == 1;
    }
}
'@

$alpha = 'slack:fixture-workspace:channel-alpha'
$account = 'fixture-workspace'
$transcript = 'Gr' + [char]0x00fc + [char]0x00df + 'e ' + [char]0x4e16 + [char]0x754c + "`r`nZweite Zeile"
$gates = @{}
$heldKeys = [Collections.Generic.HashSet[int]]::new()

function Dictation-Edit($Session) {
    return Get-Edit (Get-Window $Session) '1032'
}

function Dictation-Key($Session, [int]$Key, [bool]$Up) {
    $null = Get-App $Session
    $foreground = [VerifyWindow]::GetForegroundWindow()
    $owner = [uint32]0
    if ($foreground -ne [IntPtr]::Zero) { [VerifyWindow]::GetWindowThreadProcessId($foreground, [ref]$owner) | Out-Null }
    Assert-That ($owner -eq $Session.pid) 'Refusing key input outside the owned app'
    Assert-That ([DictationNative]::Key([uint16]$Key, $Up)) 'SendInput failed'
    if ($Up) { $null = $heldKeys.Remove($Key) } else { $null = $heldKeys.Add($Key) }
    Add-Content (Join-Path $Session.evidence 'actions.log') "dictation-key: $Key up=$Up"
}

function Dictation-Selection($Session) {
    $edit = Dictation-Edit $Session
    $handle = [IntPtr]$edit.Current.NativeWindowHandle
    $first = [uint32]0
    $last = [uint32]0
    $result = [UIntPtr]::Zero
    $ok = [DictationNative]::Selection($handle, 0x00B0, [ref]$first, [ref]$last, 2, 2000, [ref]$result)
    Assert-That ($ok -ne [IntPtr]::Zero) 'Selection read timed out'
    return @{ start = $first; end = $last }
}

function Dictation-Draft($Session, [string]$Value, [string]$Selected) {
    $edit = Dictation-Edit $Session
    $edit.SetFocus()
    $handle = [IntPtr]$edit.Current.NativeWindowHandle
    $result = [UIntPtr]::Zero
    $ok = [VerifyWindow]::WriteText($handle, 0x000C, [UIntPtr]::Zero, $Value, 2, 2000, [ref]$result)
    Assert-That ($ok -ne [IntPtr]::Zero -and $result.ToUInt64() -ne 0) 'Draft write failed'
    $actual = Read-Edit $edit
    $first = $actual.IndexOf($Selected, [StringComparison]::Ordinal)
    Assert-That ($first -ge 0 -and $actual.LastIndexOf($Selected, [StringComparison]::Ordinal) -eq $first) 'Draft selection is ambiguous'
    $last = $first + $Selected.Length
    $ok = [DictationNative]::SetSelection($handle, 0x00B1, [UIntPtr]$first, [IntPtr]$last, 2, 2000, [ref]$result)
    Assert-That ($ok -ne [IntPtr]::Zero) 'Selection write timed out'
    $selection = Dictation-Selection $Session
    Assert-That ($selection.start -eq $first -and $selection.end -eq $last) 'Draft selection did not stick'
    return @{ text = $actual; start = $first; end = $last }
}

function Dictation-OpenGates($Session) {
    foreach ($name in @('transcribe', 'publish', 'consume')) {
        if (-not $gates.ContainsKey($name)) {
            $eventName = "Local\PostboxVerify-$($Session.id)-dictation-$name"
            $gates[$name] = [Threading.EventWaitHandle]::OpenExisting($eventName)
        }
    }
}

function Dictation-Snapshot($Session, [string]$Name) {
    $state = Read-Control $Session status
    Assert-That ($state.dictation.microphone_entries -eq 0 -and $state.dictation.transcription_attempts -eq 0) 'Fixture reached a real microphone or transcription request'
    $app = Get-App $Session
    $data = @{ state = $state; text = (Read-Edit (Dictation-Edit $Session)); selection = (Dictation-Selection $Session);
               pid = $app.Id; start_ticks = $Session.startTicks; sha256 = $Session.sha256; commit = $Session.commit }
    $data | ConvertTo-Json -Depth 16 | Set-Content (Join-Path $Session.evidence "$Name.dictation.json")
    Save-Screen $Session $Name
    $ledger = Join-Path $Session.evidence 'dictation-accepted.jsonl'
    if (Test-Path $ledger) { Copy-Item $ledger (Join-Path $Session.evidence "$Name.accepted.jsonl") }
    $requests = Join-Path $Session.evidence 'bridge-requests.jsonl'
    if (Test-Path $requests) { Copy-Item $requests (Join-Path $Session.evidence "$Name.requests.jsonl") }
    $journal = Join-Path $messages 'unified-journal-v2'
    if (Test-Path $journal) {
        $snapshots = @(Get-ChildItem $journal -Filter 'snapshot.v2' -Recurse -File)
        if ($snapshots.Count -eq 1) { Copy-Item $snapshots[0].FullName (Join-Path $Session.evidence "$Name.snapshot.json") }
    }
    return $data
}

function Dictation-Start($Session) {
    $before = (Read-Control $Session status).dictation.generation
    Send-Keys $Session '^d'
    $state = Wait-Until {
        $s = (Read-Control $Session status).dictation
        if ($s.phase -eq 'recording' -and $s.generation -gt $before) { $s }
    } 'dictation recording'
    Dictation-OpenGates $Session
    return $state
}

function Dictation-Sends($Session) {
    return @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/send' })
}

function Dictation-ExpectSend($Session, [int]$Before, [string]$Expected) {
    try {
        $null = Wait-Until { @(Dictation-Sends $Session).Count -gt $Before } 'fixture send accepted' 30
    } catch {
        $observed = Dictation-Snapshot $Session 'send-timeout'
        @{ expected = $Expected; actual = $observed.text; state = $observed.state } |
            ConvertTo-Json -Depth 16 | Set-Content (Join-Path $Session.evidence 'send-timeout-comparison.json')
        throw
    }
    $rows = @(Dictation-Sends $Session)
    Assert-That ($rows.Count -eq $Before + 1) 'Unexpected duplicate send request'
    $row = $rows[-1]
    Assert-That ($row.status -eq 200 -and $row.accepted -and -not $row.duplicate) 'Fixture did not accept exactly one intent'
    Assert-That ($row.source_provider -ceq 'slack' -and $row.source_account -ceq $account -and $row.body.chat -ceq $alpha) 'Dictation sent to the wrong origin'
    Assert-That ($row.body.text -ceq $Expected -and $row.body.reply_to -ceq '' -and $row.body.client_id -cmatch '^[0-9a-f]{32}$') 'Dictation payload changed'
    $ledgerPath = Join-Path $Session.evidence 'dictation-accepted.jsonl'
    Assert-That (Test-Path $ledgerPath) 'Accepted ledger is missing'
    $matches = @(Get-Content $ledgerPath | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.client_id -ceq $row.body.client_id })
    Assert-That ($matches.Count -eq 1 -and $matches[0].text -ceq $Expected -and $matches[0].chat -ceq $alpha -and $matches[0].account -ceq $account -and $matches[0].reply_to -ceq '') 'Durable accepted payload differs'
    return $row
}

function Dictation-Original($Name) {
    $value = 'Vor' + [char]0x00e4 + "nderung old`r`nTail $Name"
    return Dictation-Draft $session $value 'old'
}

function Dictation-Expected($Original) {
    $logicalTranscript = $transcript.Replace("`r`n", "`n").Replace("`r", "`n")
    return $Original.text.Substring(0, $Original.start) + $logicalTranscript + $Original.text.Substring($Original.end)
}

function Dictation-CloseSearch($Session) {
    $palette = Get-PaletteWindow $Session
    $edit = Get-Edit $palette '1064'
    $focused = [Windows.Automation.AutomationElement]::FocusedElement
    Assert-That ($focused.Current.ProcessId -eq $Session.pid -and $focused.Current.NativeWindowHandle -eq $edit.Current.NativeWindowHandle) 'Search focus is not owned'
    $paletteHandle = [IntPtr]$palette.Current.NativeWindowHandle
    $foreground = [VerifyWindow]::GetForegroundWindow()
    $owner = [uint32]0
    if ($foreground -ne [IntPtr]::Zero) { [VerifyWindow]::GetWindowThreadProcessId($foreground, [ref]$owner) | Out-Null }
    Assert-That ($owner -eq $Session.pid -and $foreground -eq $paletteHandle) 'Search window is not foreground'
    [Windows.Forms.SendKeys]::SendWait('^k')
    Add-Content (Join-Path $Session.evidence 'actions.log') 'owned-search: ^k'
    $null = Wait-Until {
        $active = [VerifyWindow]::GetForegroundWindow()
        $active -ne $paletteHandle
    } 'search closed'
}

function Dictation-NavigationCase([string]$Name) {
    $null = Wait-Until { -not (Read-Control $session status).dictation.draining } "$Name previous worker drained"
    $original = Dictation-Original $Name
    $before = @(Dictation-Sends $session).Count
    $null = Dictation-Start $session
    $null = $gates['transcribe'].Reset()
    Send-Keys $session '^{ENTER}'
    $null = Wait-Until { (Read-Control $session status).dictation.gate_phase -eq 1 } "$Name transcription held"
    $armed = Dictation-Snapshot $session "$Name-armed"
    Assert-That ($armed.state.dictation.intent -ceq 'sending') 'Navigation case did not arm sending'
    switch ($Name) {
        'archive-roundtrip' {
            $initial = [bool]$armed.state.include_archived
            Send-Keys $session '%a'
            $null = Wait-Until { [bool](Read-Control $session status).include_archived -ne $initial } 'archive filter changed'
            Send-Keys $session '%a'
            $null = Wait-Until { [bool](Read-Control $session status).include_archived -eq $initial } 'archive filter restored'
        }
        'search-roundtrip' {
            Send-Keys $session '^f'
            $null = Get-PaletteWindow $session
            Dictation-CloseSearch $session
        }
        'other-chat' {
            Send-Keys $session '^{TAB}'
            $null = Wait-Until { (Read-Control $session status).selected.id -ceq 'slack:fixture-workspace:channel-beta' } 'Beta selected'
            $beta = Dictation-Draft $session 'Other draft stays' 'draft'
        }
    }
    $changed = Dictation-Snapshot $session "$Name-changed"
    Assert-That ($changed.state.dictation.intent -ceq 'manual' -and $changed.state.dictation.gate_phase -eq 1) 'Navigation did not preserve manual transcription'
    Assert-That (@(Dictation-Sends $session).Count -eq $before) 'Navigation sent before transcription completed'
    $null = $gates['transcribe'].Set()
    $null = Wait-Until { (Read-Control $session status).dictation.phase -eq 'idle' } "$Name completion" 30
    $finished = Dictation-Snapshot $session "$Name-finished"
    Assert-That (@(Dictation-Sends $session).Count -eq $before) 'Navigation still sent a message'
    if ($Name -eq 'other-chat') {
        Assert-That ($finished.text -ceq $beta.text) 'Other chat draft changed'
        Send-Keys $session '^+{TAB}'
        $null = Wait-Until { (Read-Control $session status).selected.id -ceq $alpha } 'Alpha restored'
        $finished = Dictation-Snapshot $session "$Name-origin"
    }
    $expected = $original.text + ' ' + $transcript.Replace("`r`n", "`n").Replace("`r", "`n")
    Assert-That ($finished.text -ceq $expected) 'Navigation lost or changed origin words'
}

function Dictation-CancelCase([string]$Name, [string]$Gate) {
    $null = Wait-Until { -not (Read-Control $session status).dictation.draining } "$Name previous worker drained"
    $original = Dictation-Original $Name
    $before = @(Dictation-Sends $session).Count
    $started = Dictation-Start $session
    if ($Gate -ne 'recording') {
        $null = $gates[$Gate].Reset()
        Send-Keys $session '^d'
        if ($Gate -eq 'transcribe') {
            $null = Wait-Until { (Read-Control $session status).dictation.gate_phase -eq 1 } "$Name held transcription"
        } elseif ($Gate -eq 'publish') {
            $null = Wait-Until { (Read-Control $session status).dictation.gate_phase -eq 2 } "$Name held publication"
        } else {
            $null = Wait-Until { (Read-Control $session status).dictation.ready } "$Name ready before consumption"
        }
    }
    $null = Dictation-Snapshot $session "$Name-before"
    Dictation-Key $session 0x1b $false
    Dictation-Key $session 0x1b $false
    $after = Dictation-Snapshot $session "$Name-cancelled"
    Dictation-Key $session 0x1b $true
    Assert-That ($after.text -ceq $original.text -and $after.selection.start -eq $original.start -and $after.selection.end -eq $original.end) 'Escape did not restore exact text and selection'
    Assert-That ($after.state.dictation.cancelled) 'Cancellation was not recorded'
    Assert-That (@(Dictation-Sends $session).Count -eq $before) 'Cancelled dictation sent a message'
    if ($Gate -in @('transcribe', 'publish')) {
        Assert-That ($after.state.dictation.draining) 'Held worker did not remain pending'
        Send-Keys $session '^d'
        $still = Dictation-Snapshot $session "$Name-still-draining"
        Assert-That ($still.state.dictation.generation -eq $started.generation -and $still.text -ceq $original.text) 'Old worker storage was reused'
    }
    if ($Gate -ne 'recording') { $null = $gates[$Gate].Set() }
    $null = Wait-Until { -not (Read-Control $session status).dictation.draining } "$Name worker drained" 35
    $final = Dictation-Snapshot $session "$Name-released"
    Assert-That ($final.text -ceq $original.text -and @(Dictation-Sends $session).Count -eq $before) 'Late completion changed the draft or sent'
}

try {
    $state = Read-Control $session status
    Assert-That ($state.selected.id -ceq $alpha -and $state.selected.provider -ceq 'slack' -and $state.selected.account -ceq $account) 'Expected synthetic Alpha as the starting chat'
    Invoke-PaletteCommand $session 'Compose message'
    $before = @(Dictation-Sends $session).Count
    $original = Dictation-Original 'happy'
    $expected = Dictation-Expected $original
    $null = Dictation-Start $session
    $null = $gates['transcribe'].Reset()
    Dictation-Key $session 0x11 $false
    Dictation-Key $session 0x0d $false
    $null = Wait-Until { (Read-Control $session status).dictation.gate_phase -eq 1 } 'happy transcription held'
    Dictation-Key $session 0x11 $true
    Dictation-Key $session 0x0d $false
    $pending = Dictation-Snapshot $session 'happy-held'
    Assert-That ($pending.state.dictation.intent -ceq 'sending' -and @(Dictation-Sends $session).Count -eq $before) 'Finish was not armed once'
    $null = $gates['transcribe'].Set()
    $sent = Dictation-ExpectSend $session $before $expected
    Dictation-Key $session 0x0d $false
    $after = Dictation-Snapshot $session 'happy-sent-held'
    Assert-That ($after.text -ceq '' -and @(Dictation-Sends $session).Count -eq $before + 1) 'Held Return fell through after sending'
    Dictation-Key $session 0x0d $true
    $sent | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'happy.accepted.json')

    $null = Wait-Until { -not (Read-Control $session status).dictation.draining } 'happy worker drained'
    $before = @(Dictation-Sends $session).Count
    $original = Dictation-Original 'transcribing'
    $expected = Dictation-Expected $original
    $null = Dictation-Start $session
    $null = $gates['transcribe'].Reset()
    Send-Keys $session '^d'
    $null = Wait-Until { (Read-Control $session status).dictation.gate_phase -eq 1 } 'transcribing held'
    Send-Keys $session '^{ENTER}'
    Send-Keys $session '^{ENTER}'
    $pending = Dictation-Snapshot $session 'transcribing-armed'
    Assert-That ($pending.state.dictation.intent -ceq 'sending' -and @(Dictation-Sends $session).Count -eq $before) 'Transcribing finish was not armed'
    $null = $gates['transcribe'].Set()
    $null = Dictation-ExpectSend $session $before $expected
    $null = Dictation-Snapshot $session 'transcribing-sent'

    foreach ($gate in @('recording', 'transcribe', 'publish', 'consume')) {
        Dictation-CancelCase "cancel-$gate" $gate
    }

    $null = Wait-Until { -not (Read-Control $session status).dictation.draining } 'cancel worker drained'
    $before = @(Dictation-Sends $session).Count
    $original = Dictation-Original 'insert-only'
    $expected = Dictation-Expected $original
    $null = Dictation-Start $session
    Send-Keys $session '^d'
    $null = Wait-Until { (Read-Control $session status).dictation.phase -eq 'idle' } 'insert-only completion' 30
    $inserted = Dictation-Snapshot $session 'insert-only'
    $canonical = $expected.Replace("`r`n", "`n").Replace("`r", "`n")
    Assert-That ($inserted.text -ceq $canonical -and @(Dictation-Sends $session).Count -eq $before) 'Insert-only dictation changed words or sent'

    foreach ($name in @('archive-roundtrip', 'search-roundtrip', 'other-chat')) {
        Dictation-NavigationCase $name
    }

    Send-Keys $session '^a{BACKSPACE}'
    Send-Keys $session 'Inactive Enter'
    Send-Keys $session '{ENTER}'
    $null = Dictation-ExpectSend $session $before 'Inactive Enter'
    $before++
    Send-Keys $session 'Inactive Ctrl Enter'
    Send-Keys $session '^{ENTER}'
    $null = Dictation-ExpectSend $session $before 'Inactive Ctrl Enter'
    $before++
    Send-Keys $session 'Inactive Escape'
    Send-Keys $session '{ESC}'
    $inactive = Dictation-Snapshot $session 'inactive-keys'
    Assert-That ($inactive.text -ceq 'Inactive Escape' -and @(Dictation-Sends $session).Count -eq $before) 'Inactive Escape changed or sent the draft'
} finally {
    foreach ($key in @($heldKeys)) { [DictationNative]::Key([uint16]$key, $true) | Out-Null }
    foreach ($gate in $gates.Values) { $null = $gate.Set(); $gate.Dispose() }
}
