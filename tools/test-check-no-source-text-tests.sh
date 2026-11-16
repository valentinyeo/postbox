#!/usr/bin/env bash
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
check="$repo/tools/check-no-source-text-tests.sh"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
mkdir -p "$temp/tools"
cp "$repo/build.zig" "$temp/build.zig"
cp "$repo"/tools/test_*.py "$repo"/tools/check_*.py "$repo/tools/source-text-limits.txt" "$temp/tools/"
bash "$check" "$repo"
bash "$check" "$temp"
fix='test the function: add a pure function with a behavior test, like src/chat_screen.zig; do not slice or read source text'
reject() {
    local status=0
    bash "$check" "$temp" > "$temp/output" 2>&1 || status=$?
    if [[ $status != 1 ]] || ! grep -Fq "$fix" "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-check-no-source-text-tests: expected rejection with fix, got %s\n' "$status" >&2
        exit 1
    fi
}
printf '\nsourceSection("start", "end")\n' >> "$temp/build.zig"
reject
cp "$repo/build.zig" "$temp/build.zig"
for reader in '(ROOT / "src/main.zig").read_text()' 'open("src/main.zig").read()' 'source("src/main.zig")'; do
    printf '%s\n' "$reader" > "$temp/tools/test_new_reader.py"
    reject
done
rm "$temp/tools/test_new_reader.py"
limit=$(awk '$1 == "build_zig_slices" { print $2 }' "$temp/tools/source-text-limits.txt")
sed -i "s/^build_zig_slices .*/build_zig_slices $((limit + 1))/" "$temp/tools/source-text-limits.txt"
bash "$check" "$temp" > "$temp/output"
grep -Fq "lower the limit for build_zig_slices to $limit" "$temp/output"
printf 'test-check-no-source-text-tests: PASS\n'
