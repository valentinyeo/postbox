param([Parameter(Mandatory)][string]$Evidence)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -cne 'true' -or -not $env:RUNNER_TEMP -or -not $env:GITHUB_WORKSPACE) {
    throw 'Historical build requires an isolated GitHub Actions runner'
}
$oldCommit = '84769d3edc2a927eab428bfdbc5e98a31fa0bfc0'
$workspace = (Resolve-Path $env:GITHUB_WORKSPACE).Path
$repository = (& git -C $workspace rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or (Resolve-Path $repository).Path -cne $workspace) { throw 'Unexpected candidate checkout' }
$candidate = (& git -C $repository rev-parse --verify 'HEAD^{commit}').Trim()
if ($LASTEXITCODE -ne 0 -or $candidate -cne $env:GITHUB_SHA) { throw 'Candidate commit does not match workflow' }
$resolved = (& git -C $repository rev-parse --verify "$oldCommit^{commit}").Trim()
if ($LASTEXITCODE -ne 0 -or $resolved -cne $oldCommit) { throw 'Pinned historical commit unavailable' }
$tree = (& git -C $repository rev-parse --verify "$oldCommit^{tree}").Trim()
if ($LASTEXITCODE -ne 0 -or $tree -notmatch '^[0-9a-f]{40}$') { throw 'Historical tree unavailable' }
$zig = (Get-Command zig -CommandType Application -ErrorAction Stop).Source
$zigVersion = (& $zig version).Trim()
if ($LASTEXITCODE -ne 0 -or $zigVersion -cne '0.16.0') { throw 'Historical build requires Zig 0.16.0' }
$artifact = [IO.Path]::GetFullPath($Evidence)
$workspacePrefix = $workspace.TrimEnd('\') + '\'
if (-not $artifact.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must be inside the workspace' }
if (Test-Path -LiteralPath $artifact) { throw 'Historical evidence already exists' }
$worktree = Join-Path $env:RUNNER_TEMP ('postbox-847-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $worktree) { throw 'Historical worktree already exists' }
New-Item -ItemType Directory -Path $artifact -Force | Out-Null
$log = Join-Path $artifact 'build.log'
$prefix = Join-Path $artifact 'old-bin'
$localCache = Join-Path $env:RUNNER_TEMP ('postbox-847-cache-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $localCache) { throw 'Historical build cache already exists' }
& git -C $repository -c core.autocrlf=false -c core.eol=lf worktree add --detach $worktree $oldCommit *> (Join-Path $artifact 'checkout.log')
if ($LASTEXITCODE -ne 0) { throw 'Historical worktree checkout failed' }
$actual = (& git -C $worktree rev-parse --verify 'HEAD^{commit}').Trim()
if ($LASTEXITCODE -ne 0 -or $actual -cne $oldCommit) { throw 'Historical checkout commit mismatch' }
$actualTree = (& git -C $worktree rev-parse --verify 'HEAD^{tree}').Trim()
if ($LASTEXITCODE -ne 0 -or $actualTree -cne $tree) { throw 'Historical checkout tree mismatch' }
$before = @(& git -C $worktree status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $before.Count -ne 0) { throw 'Historical checkout is not clean' }
$arguments = @('build', '-Dtarget=x86_64-windows-gnu', '--release=small', '-Dversion=0.0.526', '--prefix', $prefix, '--cache-dir', $localCache)
Push-Location $worktree
try {
    & $zig @arguments *> $log
    $buildExit = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($buildExit -ne 0) { throw "Historical Zig build failed: $buildExit" }
$after = @(& git -C $worktree status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $after.Count -ne 0) { throw 'Historical checkout changed during build' }
$actualAfter = (& git -C $worktree rev-parse --verify 'HEAD^{commit}').Trim()
if ($LASTEXITCODE -ne 0 -or $actualAfter -cne $oldCommit) { throw 'Historical checkout changed revision' }
$files = @('Messages.exe', 'wazigctl.exe', 'postboxctl.exe', 'IBMPlexSans-Regular.ttf', 'IBMPlexSans-Medium.ttf', 'IBMPlexSans-SemiBold.ttf', 'IBMPlexSans-Bold.ttf', 'IBMPlexSans-Italic.ttf', 'IBMPlexMono-Regular.ttf', 'IBM-Plex-LICENSE.txt')
$hashes = [ordered]@{}
foreach ($name in $files) {
    $path = Join-Path (Join-Path $prefix 'bin') $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) { throw "Historical build missing: $name" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($name.EndsWith('.ttf') -or $name.EndsWith('.txt')) {
        $original = Join-Path (Join-Path $worktree 'assets') $name
        if (-not (Test-Path -LiteralPath $original -PathType Leaf) -or (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash) { throw "Historical bundled asset differs: $name" }
    }
    $hashes[$name] = @{ sha256 = $hash; bytes = (Get-Item -LiteralPath $path).Length; path = "old-bin/bin/$name" }
}
if ($hashes['wazigctl.exe'].sha256 -cne $hashes['postboxctl.exe'].sha256) { throw 'Historical control binaries differ' }
$sourceHashes = [ordered]@{}
$sourceNames = @('build.zig', 'src/main.zig', 'src/wazigctl.zig', 'src/font_config.zig') + @($files | Where-Object { $_.EndsWith('.ttf') -or $_.EndsWith('.txt') } | ForEach-Object { 'assets/' + $_ })
foreach ($name in $sourceNames) {
    $path = Join-Path $worktree $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Historical source missing: $name" }
    $expectedBlob = (& git -C $repository rev-parse --verify "${oldCommit}:$name").Trim()
    if ($LASTEXITCODE -ne 0) { throw "Historical source object unavailable: $name" }
    $actualBlob = (& git -C $worktree hash-object --no-filters $path).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualBlob -cne $expectedBlob) { throw "Historical source bytes differ: $name" }
    $sourceHashes[$name] = @{ sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(); git_blob = $actualBlob }
}
@{
    old_commit = $oldCommit; old_tree = $tree; checked_out_commit = $actual; checkout_after = $actualAfter
    worktree = $worktree; candidate_checkout = $workspace; candidate_commit = $candidate
    clean_before = $true; clean_after = $true; zig_path = $zig; zig_version = $zigVersion
    build_arguments = $arguments; build_exit = $buildExit; build_log = 'build.log'
    source_sha256 = $sourceHashes; files = $hashes
    purpose = 'historical test input; not release or updater'
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $artifact 'provenance.json') -Encoding utf8
