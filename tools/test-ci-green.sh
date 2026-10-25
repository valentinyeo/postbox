#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
check="$script_dir/ci-green.sh"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT

cat > "$temp/gh" <<'GH'
#!/usr/bin/env bash
n=$(($(cat "$FAKE_DIR/calls" 2>/dev/null || echo 0) + 1))
echo "$n" > "$FAKE_DIR/calls"
line=$(sed -n "${n}p" "$FAKE_DIR/replies")
[ -n "$line" ] || line=$(tail -1 "$FAKE_DIR/replies")
[ "$line" = "FAIL" ] && exit 1
echo "$line"
GH
chmod +x "$temp/gh"

sha=41e50ec1f63ece1f275dd3e223f6117da870e472
running='[{"status":"in_progress","conclusion":""}]'
green='[{"status":"completed","conclusion":"success"}]'
red='[{"status":"completed","conclusion":"failure"}]'

expect() {
    local name=$1 want=$2 wait=$3; shift 3
    rm -f "$temp/calls"
    printf '%s\n' "$@" > "$temp/replies"
    status=0
    PATH="$temp:$PATH" FAKE_DIR="$temp" GITHUB_REPOSITORY=yeo/wazig \
        CI_GREEN_WAIT_SECONDS="$wait" CI_GREEN_POLL_SECONDS=0 \
        bash "$check" "$sha" > "$temp/out" 2>&1 || status=$?
    if [ "$status" -ne "$want" ]; then
        cat "$temp/out" >&2
        printf 'test-ci-green: FAIL %s: want exit %s, got %s\n' "$name" "$want" "$status" >&2
        exit 1
    fi
    printf 'test-ci-green: ok %s\n' "$name"
}

expect "WAZI-142 auto-release at 14:31:00Z waits for the running ci, then tags" 0 60 "$running" "$running" "$green"
expect "WAZI-142 old one-shot check refused the same case" 1 0 "$running"
expect "red ci refuses" 1 60 "$red"
expect "ci turning red while waiting refuses" 1 60 "$running" "$red"
expect "no ci run refuses" 1 60 '[]'
expect "failed query refuses" 1 60 FAIL
expect "green beside a red rerun tags" 0 60 "[{\"status\":\"completed\",\"conclusion\":\"failure\"},{\"status\":\"completed\",\"conclusion\":\"success\"}]"

workflow="$script_dir/../.github/workflows/auto-release.yml"
picker="$script_dir/auto-release-pick.sh"
if ! grep -Fq 'bash tools/auto-release-pick.sh "${GITHUB_REPOSITORY}" origin/main' "$workflow" \
    || ! grep -Fq 'bash "$script_dir/ci-green.sh" "$sha"' "$picker"; then
    printf 'test-ci-green: FAIL auto-release picker must prove CI-green with tools/ci-green.sh\n' >&2
    exit 1
fi
printf 'test-ci-green: ok auto-release picker uses ci-green.sh\n'

app_gate="$(sed -n '/- name: Release only when the app itself changed/,/- name: Work out the next version/p' "$workflow")"
if ! grep -Fq 'GH_TOKEN: ${{ github.token }}' <<< "$app_gate" \
    || ! grep -Fq 'gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate' <<< "$app_gate" \
    || ! grep -Fq 'select(.draft == false and .prerelease == false)' <<< "$app_gate" \
    || ! grep -Fq 'last="$(printf '\''%s\n'\'' "${releases}"' <<< "$app_gate"; then
    printf 'test-ci-green: FAIL app-change baseline must use authenticated published releases\n' >&2
    exit 1
fi
printf 'test-ci-green: ok app-change baseline uses published releases\n'

version_step="$(sed -n '/- name: Work out the next version/,/- name: Tag it/p' "$workflow")"
if ! grep -Fq 'last_tag="$(git tag -l '\''v*'\''' <<< "$version_step" \
    || ! grep -Fq 'sort -V | tail -1' <<< "$version_step" \
    || ! grep -Fq 'last_tag="${last_tag:-v0.0.0}"' <<< "$version_step"; then
    printf 'test-ci-green: FAIL next version must advance beyond existing tags\n' >&2
    exit 1
fi
printf 'test-ci-green: ok next version uses existing tags\n'
