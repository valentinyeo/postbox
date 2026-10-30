# Hub storage recovery

## Sub-features

- Checkpoint, terminal and acknowledgement replacement failures.
- Durable identity, private files and manual recovery.

## How to get to it (user POV)

- Send messages through the normal hub composer.

## Driving it with PowerShell UI Automation

- Run `feature=hub-fault` on GitHub Actions.
- The isolated fixture drives real restart and retry.

## Gotchas

- Fixture acceptance does not prove production deduplication.
- Other fault stages and rollback need separate proof.
