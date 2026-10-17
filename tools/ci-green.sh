#!/usr/bin/env bash
set -uo pipefail

sha="${1:?usage: ci-green.sh <sha>}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
wait_seconds="${CI_GREEN_WAIT_SECONDS:-1800}"
poll_seconds="${CI_GREEN_POLL_SECONDS:-20}"
SECONDS=0

while :; do
    runs="$(gh run list -R "$repo" -w ci -b main --commit "$sha" -L 50 --json status,conclusion 2>/dev/null)" || runs=""
    if [ -z "$runs" ]; then
        echo "could not query ci runs for main HEAD ${sha}; refusing to tag" >&2
        exit 1
    fi
    read -r ok pending < <(echo "$runs" | jq -r '[(map(select(.conclusion == "success")) | length), (map(select(.status != "completed")) | length)] | "\(.[0]) \(.[1])"') || { ok=""; pending=""; }
    if ! [ "${ok:-}" -ge 0 ] 2>/dev/null || ! [ "${pending:-}" -ge 0 ] 2>/dev/null; then
        echo "could not read ci runs for main HEAD ${sha}; refusing to tag" >&2
        exit 1
    fi
    if [ "$ok" -ge 1 ]; then
        echo "ci is green on main HEAD ${sha}"
        exit 0
    fi
    if [ "$pending" -eq 0 ]; then
        echo "no successful ci run for main HEAD ${sha}; refusing to tag" >&2
        exit 1
    fi
    if [ "$SECONDS" -ge "$wait_seconds" ]; then
        echo "ci on main HEAD ${sha} still running after ${wait_seconds}s; refusing to tag" >&2
        exit 1
    fi
    echo "ci on main HEAD ${sha} is still running; waiting"
    sleep "$poll_seconds"
done
