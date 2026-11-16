#!/usr/bin/env bash
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
check="$repo/tools/check-no-empty-catch.sh"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
mkdir -p "$temp/tools" "$temp/src"
cp "$repo"/src/*.zig "$temp/src/"
cp "$repo/tools/empty-catch-limits.txt" "$temp/tools/"
bash "$check" "$repo"
bash "$check" "$temp"
fix="handle the error: log it with the app's log function, return it, or use \`catch |err| log(...)\`; do not swallow it with an empty catch. Lower the limit when you remove cases."
reject() {
    local status=0
    bash "$check" "$temp" > "$temp/output" 2>&1 || status=$?
    if [[ $status != 1 ]] || ! grep -Fq "$fix" "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-check-no-empty-catch: expected rejection with fix, got %s\n' "$status" >&2
        exit 1
    fi
}
for catch in 'catch {}' 'catch |_| {}' 'catch |err| {}' $'catch\n |err| \n{ \n}'; do
    printf '\n%s\n' "$catch" >> "$temp/src/main.zig"
    reject
    cp "$repo/src/main.zig" "$temp/src/main.zig"
done
printf 'catch {}\n' > "$temp/src/new.zig"
reject
printf '%s\n' '// catch {}' 'const s = "catch {}";' 'const q = "\\\" catch {}";' > "$temp/src/new.zig"
bash "$check" "$temp" > "$temp/output"
sed -i 's/^src\/main.zig 42$/src\/main.zig 43/' "$temp/tools/empty-catch-limits.txt"
bash "$check" "$temp" > "$temp/output"
grep -Fq 'lower the limit for src/main.zig to 42' "$temp/output"
printf 'test-check-no-empty-catch: PASS\n'
