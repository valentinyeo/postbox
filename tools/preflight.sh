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
run "$ZIG" build test
run "$ZIG" test src/stretch.zig
run "$ZIG" build -Dtarget=x86_64-windows-gnu --release=small
run bash tools/lint-repeats.sh .
