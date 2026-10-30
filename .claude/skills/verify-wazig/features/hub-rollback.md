# Hub rollback loader boundary

## Sub-features

- Complete migration, historical loader and shared-profile exclusion.
- Historical offline cache cleanup with disposable Windows user.

## How to get to it (user POV)

- Upgrade protected outbox work before rolling back.

## Driving it with PowerShell UI Automation

- Run `feature=hub-rollback` on GitHub Actions.
- The fixture builds and launches the pinned old executable.

## Gotchas

- This is not complete rollback proof.
- Old writes and re-upgrade remain unimplemented.
- Offline cleanup requires an isolated Actions runner.
- Partial migration crashes, capacity and allocator remain unimplemented.
- Voice and full routing proof remain unimplemented.
