# Interrupted hub migration

## Sub-features

- Interruption between quarantine and attachment protection.
- Historical offline cache pruning and re-upgrade recovery.

## How to get to it (user POV)

- Upgrade queued image work, then roll back.

## Driving it with PowerShell UI Automation

- Run `feature=hub-migration-crash` on GitHub Actions.
- Retry recovered work using the actual mouse.

## Gotchas

- Current recovery may fail with lost attachment.
- This is not complete rollback proof.
- Other crashes, capacity and allocator remain untested.
