#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ZIG="${ZIG:-$HOME/.local/zig-0.16.0/zig}"
export ZIG
python3 tools/telegram_fake.py "$@"
