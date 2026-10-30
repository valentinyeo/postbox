. "$PSScriptRoot/paste-image.ps1"

function Process-Sid([int]$PidValue) {
    $row = Get-CimInstance Win32_Process -Filter "ProcessId = $PidValue" -ErrorAction Stop
    Assert-That ($null -ne $row) 'Owned process disappeared'
    $owner = Invoke-CimMethod -InputObject $row -MethodName GetOwnerSid -ErrorAction Stop
    Assert-That ($owner.ReturnValue -eq 0 -and $owner.Sid) 'Process owner unavailable'
    return $owner.Sid
}

function Save-RollbackRequests($Session, [string]$Name) {
    $rows = @(Read-BridgeRequests $Session)
    ConvertTo-Json -InputObject $rows -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.requests.json")
    return $rows
}

function Get-RollbackFiles([string]$Folder) {
    $base = [IO.Path]::GetFullPath($Folder).TrimEnd('\') + '\'
    $rows = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $Folder -Recurse -File | Sort-Object FullName)) {
        Assert-That ($file.FullName.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) 'Profile file escaped owned root'
        $rows += @{ path = $file.FullName.Substring($base.Length).Replace('\', '/'); bytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    return ,$rows
}

function Get-MutexProtectedFiles {
    $rows = @()
    foreach ($row in (Get-RollbackFiles (Join-Path $messages 'unified-journal-v2'))) {
        $rows += @{ path = 'unified-journal-v2/' + $row.path; bytes = $row.bytes; sha256 = $row.sha256 }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $messages -Filter '*outbox.jsonl' -File | Sort-Object Name)) {
        $rows += @{ path = $file.Name; bytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    return ,$rows
}

function Save-RollbackPrivate($Session, [string]$Name) {
    $null = Get-App $Session
    $folder = Join-Path $messages 'unified-journal-v2'
    $rows = Get-RollbackFiles $folder
    ConvertTo-Json -InputObject $rows -Depth 8 | Set-Content (Join-Path $Session.evidence "$Name.private.json")
    $snapshots = @(Get-ChildItem -LiteralPath $folder -Filter 'snapshot.v2' -Recurse -File)
    Assert-That ($snapshots.Count -eq 1) 'Rollback snapshot missing'
    Copy-Item $snapshots[0].FullName (Join-Path $Session.evidence "$Name.snapshot.json")
    return Get-Content $snapshots[0].FullName -Raw | ConvertFrom-Json
}

function Stop-RollbackApp($Session) {
    $old = Get-App $Session
    Invoke-PaletteCommand $Session 'Quit Postbox'
    $null = Wait-Until { $old.Refresh(); $old.HasExited } 'owned rollback process stopped'
}

function Start-RollbackApp($Session, $Info, [string]$Exe, [string]$Ctl, [string]$Hash) {
    $Info.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    Assert-That ($Info.Environment['LOCALAPPDATA'] -ceq $local -and $Info.Environment['WAZIG_VERIFY_ROOT'] -ceq $Session.root) 'Rollback profile changed'
    Assert-That ((Get-FileHash $Exe -Algorithm SHA256).Hash -ceq $Hash) 'Rollback executable changed'
    $child = [Diagnostics.Process]::Start($Info)
    $Session.pid = $child.Id
    $Session.startTicks = $child.StartTime.ToUniversalTime().Ticks.ToString()
    $Session.exe = $Exe
    $Session.ctl = $Ctl
    $Session.sha256 = $Hash
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    $null = Wait-Until { $child.Refresh(); if ($child.HasExited) { throw "Rollback app exited: $($child.ExitCode)" }; $child.MainWindowHandle -ne [IntPtr]::Zero } 'rollback app window'
    [VerifyWindow]::ShowWindow($child.MainWindowHandle, 3) | Out-Null
    $null = Wait-Until { (Read-Control $Session status).chat_count -gt 0 } 'rollback chats'
    $null = Get-App $Session
    return $child
}

