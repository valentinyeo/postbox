#!/usr/bin/env bash
set -euo pipefail
cd "${1:-$(git rev-parse --show-toplevel)}"
if [ -z "${ZIG:-}" ]; then
    if [ -x "$HOME/.local/zig-0.16.0/zig" ]; then ZIG="$HOME/.local/zig-0.16.0/zig"; else ZIG=zig; fi
fi
version="$("$ZIG" version)"
if [ "$version" != "0.16.0" ]; then
    echo "preflight: $ZIG is Zig $version; use Zig 0.16.0 (set ZIG=~/.local/zig-0.16.0/zig)." >&2
    exit 1
fi
run() { echo "preflight: $*"; "$@"; }
run "$ZIG" fmt --check src build.zig
run node tools/check-fonts.mjs
run node --test tools/check-fonts.test.mjs
run "$ZIG" build test
if [ "${WAZIG_WINE_TESTS:-0}" = "1" ]; then
    raster_temp=$(mktemp -d)
    trap 'rm -rf -- "$raster_temp"' EXIT
    run "$ZIG" test src/smooth_shapes.zig -target x86_64-windows-gnu -lc -lgdi32 -luser32 -lmsimg32 --test-no-exec -femit-bin="$raster_temp/smooth-test.exe"
    run xvfb-run -a wine "$raster_temp/smooth-test.exe"
    run "$ZIG" test src/text_draw.zig -O ReleaseSmall -target x86_64-windows-gnu -lc -lgdi32 -luser32 --test-no-exec -femit-bin="$raster_temp/text-test.exe"
    run xvfb-run -a wine "$raster_temp/text-test.exe"
fi
run python3 tools/test_outbox_runtime.py --zig "$ZIG" --negative-controls
run "$ZIG" test src/stretch.zig
run "$ZIG" build -Dtarget=x86_64-windows-gnu --release=small
run du -h zig-out/bin/Messages.exe
run bash tools/lint-repeats.sh .
run python3 -m unittest discover -s tools -p 'test_*.py'
run python3 tools/check_cache_keys.py
run node --test tools/strip-comments.test.js
run node tools/strip-comments.mjs --check
run git fetch --quiet --no-tags origin '+refs/pull/*/head:refs/remotes/pr/*'
run bash tools/test-preflight-guard.sh
run bash tools/test-agent-setup.sh
run bash tools/test-lint-repeats.sh
run bash tools/test-people-index-speed.sh
run bash tools/test-ci-green.sh
