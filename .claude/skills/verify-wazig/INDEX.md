# Verification index

Journey names, PR coverage, fixture modes and dispatch files are registered once in [journeys.json](../../../tools/verify-wazig/journeys.json). Each registered name has a corresponding `features/<name>.md` recipe.

Bounded recent-change coverage lives in [features/README.md](features/README.md). Launch and evidence rules live in [SKILL.md](SKILL.md); [RULE-MAP.md](RULE-MAP.md) links feature-specific acceptance rules.

A registered journey is coverage intent, not proof of a successful run. Runtime evidence must come from the exact commit's GitHub Windows run.
