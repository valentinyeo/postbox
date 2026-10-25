# Unified palette search

## Sub-features

- `search-focus`: Ctrl+F and slash focus palette edit 1064 in exact entity-search mode, including from an empty list.
- `search-match`: reuse the former bar's case-insensitive name/identifier matching, current-view/archive/unread filters and ordering.
- `search-empty`: no-match and unread-only empty-list cases remain searchable.
- `search-clear`: Escape clears the query and restores the list.
- `search-parity`: one shared 24-query contract, two shortcut samples per query and ordered provider/account/id evidence.
- `search-removal`: no sidebar edit 1008 or native child, no old cue and no reserved layout slot.
- `search-groups`: chat results precede the separate command group in search mode; archive matches both a thread and commands.
- `search-archived-ink`: measure archived palette text against a live result using screenshot pixels.

## How to get to it (user POV)

Press Ctrl+F, or `/` outside an editable field. Ctrl+K still opens the default fuzzy command palette; its Search chats command opens the same box in exact entity-search mode. Escape clears search. The archive switch and account view still govern entity search.

## Driving it with PowerShell UI Automation

Dispatch `feature=search`. The isolated unified fake hub reads synthetic rows and message text from `tools/verify-wazig/search-queries.json`; the journey reads the same file's queries. No provider accounts are used.

The same journey detects edit 1008 on the evidence-only red build and types into the bar. On the fixed build it types into palette edit 1064. Each query is repeated through Ctrl+F and slash, recording focus, native list labels/count, read-only state and ordered identities in `search-parity.json`. The complete file survives the deliberate red failure at the subsequent bar-removal assertion. No red artifact is accepted as a successful fixed-build journey.

Fixed evidence also includes `search-removal.json`, `search-shortcuts.json`, `search-archive.json`, `search-archive.png`, `search-match.png` and `empty.png`. The search journey runs the palette command-discovery and removed-Status assertions. The workflow additionally runs the standalone offline palette journey under `palette/`, preserving the no-configured-backend assertion.

Download both `verify-wazig-search` artifacts into different directories and run:

```sh
python3 tools/verify-wazig/check-search-evidence.py evidence/fixed --baseline evidence/red
```

This requires identical query-file hashes and cases, different build revisions/hashes, exact identity order within each run and across runs, fixed-build focus/removal/group assertions, measurable archived dimming, isolation and cleanup. Inspect the screenshots too. Run `check-evidence.py evidence/fixed/palette` for the separate offline palette evidence.

## Gotchas

The former bar searches names and identifiers, not message bodies or account labels. The real fixture message words rendezvous, agenda and milestone deliberately record empty identity lists on both builds; this is parity, not a claim of new full-text search. Account queries use real source identifiers. Contacts are synthetic cached contact chats; this fixture does not claim standalone provider-contact-index coverage.

Slash in an editable field remains text. Entity rows are read from the native palette and checked against the recorded identity order, not inferred from a result count. A missing or reordered result fails. Local source validators do not constitute Windows runtime or cross-run parity proof.
