# Interrupted attachment protection

## Sub-features

- Retry after protection and before journal rename.

## How to get to it (user POV)

- Upgrade queued image work, then roll back.

## Driving it with PowerShell UI Automation

- Run `feature=hub-migration-before-rename` on GitHub Actions.
- Retry recovered work using the actual mouse.

## Gotchas

- The old app must leave the journal unchanged.
- This is not complete rollback proof.
