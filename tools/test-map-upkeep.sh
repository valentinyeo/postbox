#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
case "$1 $2" in
    "run list") [ -n "${FAKE_RUN:-}" ] && echo '{"databaseId":9,"url":"https://example.test/run/9"}' ;;
    "run view") [ -n "${FAKE_FAILED:-}" ] && echo "$FAKE_FAILED" ;;
    "issue list") [ -n "${FAKE_ISSUE:-}" ] && echo "$FAKE_ISSUE" ;;
esac
exit 0
SH
chmod +x "$TMP/bin/gh"

run_case() {
    local name="$1" expect="$2" forbid="$3"
    shift 3
    : > "$TMP/log"
    env PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" "$@" bash "$ROOT/tools/map-upkeep.sh" > "$TMP/out" 2>&1 || {
        echo "FAIL $name: script exited non-zero"
        cat "$TMP/out"
        exit 1
    }
    if [ -n "$expect" ] && ! grep -q "$expect" "$TMP/log"; then
        echo "FAIL $name: expected a call matching '$expect'"
        cat "$TMP/log"
        exit 1
    fi
    if [ -n "$forbid" ] && grep -q "$forbid" "$TMP/log"; then
        echo "FAIL $name: unexpected call matching '$forbid'"
        cat "$TMP/log"
        exit 1
    fi
    echo "ok $name"
}

run_case clean-no-issue '' 'issue \(create\|edit\|close\)' FAKE_RUN=1
run_case clean-closes-open-issue 'issue close 7' 'issue \(create\|edit\)' FAKE_RUN=1 FAKE_ISSUE=7
run_case red-nightly-opens-one-issue 'issue create' 'issue \(edit\|close\)' FAKE_RUN=1 FAKE_FAILED='verify (search, true)'
run_case red-nightly-updates-existing-issue 'issue edit 7' 'issue \(create\|close\)' FAKE_RUN=1 FAKE_FAILED='verify (search, true)' FAKE_ISSUE=7
