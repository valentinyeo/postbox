# Hub rollback loader boundary

## Sub-features

- Complete migration, historical loader and shared-profile exclusion.

## How to get to it (user POV)

- Upgrade protected outbox work before rolling back.

## Driving it with PowerShell UI Automation

- Run `feature=hub-rollback` on GitHub Actions.
- The fixture builds and launches the pinned old executable.

## Gotchas

- This is not complete rollback proof.
- Historical cleanup, old writes and re-upgrade remain unimplemented.
- Partial migration crashes, capacity and allocator remain unimplemented.
- Voice and full routing proof remain unimplemented.
