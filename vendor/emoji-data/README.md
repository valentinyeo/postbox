# Slack standard emoji data

`src/slack_emoji.tsv` is generated from the public emoji-data `emoji.json`, revision `13ee711e222ea17fe537bfea953c687866f16411` (MIT; license beside this file).

Upstream SHA-256: `8736d721991e48c41c57acc46b65e5d32258a45e4bcdebcc6012f420f81e775d`.

Regenerate with `python3 tools/generate-slack-emoji.py`. Every `short_names` alias and every `skin_variations` sequence is included, with Slack tone numbers 2–6. `--source <emoji.json> --check` checks reproducibility offline. The generator pins the public source URL; the app embeds only the generated table and needs no dataset download or extra runtime.

Generated table SHA-256: `0df5b13a416662c7d84266ed31b3499c7ae4ef99ba191854aa2fc9537b38f70a` (4,205 entries). Public upstream authorship is retained verbatim in the required MIT license; no private user or workspace data is included.
