#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
picker="$script_dir/auto-release-pick.sh"
workflow="$script_dir/../.github/workflows/auto-release.yml"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
mkdir "$temp/bin" "$temp/repo"

cat > "$temp/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = api ]; then
    if [ "$2" = repos/yeo/wazig/releases ]; then
        printf 'v0.9.202\n'
    else
        printf '%s\n' "$*" >> "$FAKE_DIR/writes"
    fi
    exit 0
fi
if [ "$1 $2" = 'workflow run' ]; then
    printf '%s\n' "$*" >> "$FAKE_DIR/writes"
    exit 0
fi
[ "$1 $2 $3 $4 $5 $6 $7 $8" = "run list -R yeo/wazig -w ci -b main" ] || exit 2
[ "$9" = --commit ] || exit 2
sha="${10}"
printf '%s\n' "$sha" >> "$FAKE_DIR/calls"
if [ -f "$FAKE_DIR/fail" ]; then
    exit 1
fi
if grep -Fxq "$sha" "$FAKE_DIR/green"; then
    printf '[{"status":"completed","conclusion":"success"}]\n'
else
    printf '[{"status":"completed","conclusion":"failure"}]\n'
fi
GH
chmod +x "$temp/bin/gh"
export PATH="$temp/bin:$PATH" FAKE_DIR="$temp"

cd "$temp/repo"
git init -q
git config user.name 'Release test'
git config user.email 'release-test@example.invalid'
git -c commit.gpgsign=false commit --allow-empty -qm root
root=$(git rev-parse HEAD)
mkdir src
printf 'app change\n' > src/app.txt
git add src/app.txt
git -c commit.gpgsign=false commit -qm parent
parent=$(git rev-parse HEAD)
git -c commit.gpgsign=false commit --allow-empty -qm 'head [skip release]'
head=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$head"

expect() {
    local name=$1 want=$2; shift 2
    printf '%s\n' "$@" > "$temp/green"
    : > "$temp/calls"
    local got
    got=$(bash "$picker" yeo/wazig origin/main 2> "$temp/err")
    if [ "$got" != "$want" ]; then
        cat "$temp/err" >&2
        printf 'test-auto-release-pick: FAIL %s: want %s, got %s\n' "$name" "$want" "$got" >&2
        exit 1
    fi
    printf 'test-auto-release-pick: ok %s\n' "$name"
}

expect 'green untagged HEAD wins' "$head" "$head" "$parent"
expect 'red HEAD falls back to green parent' "$parent" "$parent" "$root"
expect 'no green commit gives nothing' ''
touch "$temp/fail"
expect 'failed green queries give nothing' '' "$head" "$parent"
rm "$temp/fail"

side=$(printf 'side\n' | git -c commit.gpgsign=false commit-tree "$(git write-tree)" -p "$parent")
merge=$(printf 'merge\n' | git -c commit.gpgsign=false commit-tree "$(git write-tree)" -p "$head" -p "$side")
git update-ref refs/remotes/origin/main "$merge"
expect 'first-parent walk ignores green side branch' "$head" "$head" "$side"
expect 'side-branch green alone gives nothing' '' "$side"
git update-ref refs/remotes/origin/main "$head"

git -c tag.gpgsign=false tag non-release "$head"
expect 'non-v tag does not block release' "$head" "$head"
git -c tag.gpgsign=false tag -am release v0.9.204 "$head"
expect 'newest green already tagged gives nothing' '' "$head" "$parent" "$root"
if [ "$(cat "$temp/calls")" != "$head" ]; then
    printf 'test-auto-release-pick: FAIL walked beyond newest green tagged commit\n' >&2
    exit 1
fi

if bash "$picker" yeo/wazig missing-ref > "$temp/out" 2> "$temp/err"; then
    printf 'test-auto-release-pick: FAIL invalid ref must fail\n' >&2
    exit 1
fi
[ ! -s "$temp/out" ]
printf 'test-auto-release-pick: ok invalid ref fails without a target\n'
workflow_step() {
    awk -v name="$1" '
        /^      - name:/ { active = ($0 == "      - name: " name); run = 0 }
        active && /^        run: \|$/ { run = 1; next }
        active && run && /^          / { sub(/^          /, ""); print }
    ' "$workflow"
}

git -c tag.gpgsign=false tag v0.9.202 "$root"
export GITHUB_REPOSITORY=yeo/wazig GITHUB_ENV="$temp/env" GITHUB_STEP_SUMMARY="$temp/summary"
export target_sha="$parent" BUMP=patch
: > "$GITHUB_ENV"
workflow_step 'Honour [skip release]' | bash -euo pipefail
[ ! -s "$GITHUB_ENV" ]
target_sha="$head" bash -euo pipefail < <(workflow_step 'Honour [skip release]')
grep -Fxq 'skip=true' "$GITHUB_ENV"
: > "$GITHUB_ENV"
printf 'test-auto-release-pick: ok skip-release reads target, not HEAD\n'
workflow_step 'Release only when the app itself changed' | bash -euo pipefail
[ ! -s "$GITHUB_ENV" ]
target_sha="$root" bash -euo pipefail < <(workflow_step 'Release only when the app itself changed')
grep -Fxq 'skip=true' "$GITHUB_ENV"
: > "$GITHUB_ENV"
printf 'test-auto-release-pick: ok app diff uses published release through target\n'
workflow_step 'Work out the next version' | bash -euo pipefail
grep -Fxq 'next_tag=v0.9.205' "$GITHUB_ENV"
export next_tag=v0.9.205
workflow_step 'Tag it' | bash -euo pipefail
printf 'api repos/yeo/wazig/git/refs -f ref=refs/tags/v0.9.205 -f sha=%s\nworkflow run release.yml -R yeo/wazig --ref v0.9.205\n' "$parent" > "$temp/want-writes"
cmp "$temp/want-writes" "$temp/writes"
printf 'test-auto-release-pick: ok fresh version tags target and dispatches new tag\n'
: > "$GITHUB_ENV"
workflow_step 'Skip if this commit is already released' | bash -euo pipefail
[ ! -s "$GITHUB_ENV" ]
target_sha="$head" bash -euo pipefail < <(workflow_step 'Skip if this commit is already released')
grep -Fxq 'skip=true' "$GITHUB_ENV"
printf 'test-auto-release-pick: ok already-tagged guard reads target\n'
printf 'All auto-release-pick tests passed.\n'
