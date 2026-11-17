# Adoption evidence

These are local structural checks, before committing adoption.
They are not trusted GitHub execution attestations.
The snapshot uses this PR's proposed policy.
Its three passes cannot authorize merging.

- `before-map.log`: shared coverage failed before configuration.
- `gate-snapshot.json`: thirteen proposed-policy check results.
- `removed-entry.log`: bounded inventory rejects missing CLI entry.
- `restored-entry.log`: restored bounded inventory passes.
- `shared-gate-removed-entry.log`: Zig still blocks shared coverage.

The shared gate cannot compare Zig entries yet.
Its missing-entry negative control remains unproven for Postbox.
Hosted adoption tests also run upstream fixture controls.
Those fixtures cannot certify Postbox's custom handlers.
