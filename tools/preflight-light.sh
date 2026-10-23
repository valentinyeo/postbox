#!/usr/bin/env bash
set -euo pipefail
cd "${1:-$(git rev-parse --show-toplevel)}"
run() { echo "preflight-light: $*"; "$@"; }
run bash tools/lint-repeats.sh .
run node tools/strip-comments.mjs --check
run node tools/check-fonts.mjs
run python3 tools/check_cache_keys.py
run python3 tools/verify-wazig/check-map.py
if [ -n "${PRIVATE_MARKERS:-}" ]; then
    run python3 tools/check_private_markers.py
else
    echo 'preflight-light: private-marker scan skipped (PRIVATE_MARKERS unavailable); CI enforces it.'
fi
run node --test tools/check-fonts.test.mjs tools/strip-comments.test.js
(
    cd tools
    run python3 -m unittest test_check_cache_keys test_check_private_markers test_pin_icon test_tdlib_release test_slack_sort test_slack_threads test_search_center
)
echo 'preflight-light: all checks passed'
