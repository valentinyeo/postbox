# Interrupted hub migration

## Sub-features

- Interruption after the legacy journal was quarantined and its attachments were protected, before the next start imports that record.
- Historical offline cache pruning and re-upgrade recovery.

## How to get to it (user POV)

- Upgrade queued image work, then roll back.

## Driving it with PowerShell UI Automation

- Run `feature=hub-migration-crash` on GitHub Actions. The fixture switch stops the new build at `after-quarantine-before-import` (exit 86): `unifiedImportRecord` has already copied the queued image into `imports-files/<token>/payload`, and the journal is a `.pending` file under `imports/`.
- The next start must recover one `held`, `ambiguous` record with `attempt_serial` 0, the original attachment bytes and hash inside its owned file, and no `/v1/wazig/send` for 45 seconds. A real mouse click on the failed bubble then sends one accepted request with a fresh 32-character client_id.

## Gotchas

- The crash point is fixed by the fixture switch. The pre-rename case is `hub-migration-before-rename`; other crash points, capacity and allocator failures remain untested.
- This is not complete rollback proof.
- Other crashes, capacity and allocator remain untested.
