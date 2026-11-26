# Hub rollback loader boundary

## Sub-features

- Complete migration, historical loader and shared-profile exclusion.
- Historical offline cache cleanup with disposable Windows user.

## How to get to it (user POV)

- Upgrade protected outbox work before rolling back.

## Driving it with PowerShell UI Automation

- Run `feature=hub-rollback` on GitHub Actions.
- The verify workflow builds the pinned old executable with `tools/verify-wazig/build-historical-847.ps1` (commit 84769d3); the journey checks its provenance and hashes, then launches it.

## Gotchas

- This is not complete rollback proof.
- Old writes remain unimplemented. Re-upgrade recovery is covered by [hub-migration-crash](hub-migration-crash.md) and [hub-migration-before-rename](hub-migration-before-rename.md), which run the same re-upgrade script; the before-rename variant only changes the exit code and pending-journal checks.
- Offline cleanup requires an isolated Actions runner.
- Interrupted migration is covered by [hub-migration-crash](hub-migration-crash.md) and [hub-migration-before-rename](hub-migration-before-rename.md). Other crashes, capacity and allocator remain unimplemented.
- Voice and full routing proof remain unimplemented.
