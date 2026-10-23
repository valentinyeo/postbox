#!/usr/bin/env bash
set -uo pipefail

if (( $# != 4 )); then
    printf 'usage: %s <pr-info.json> <files.json> <behind_by> <owner>\n' "$0" >&2
    exit 2
fi
info_file=$1
files_file=$2
behind_by=$3
REPO_OWNER=$4

required='["ci","tdlib","windows-smoke","no-comments","unfurl-verification","private-markers","secret-scan","pr-title","notify-release","tdlib-cache / cache"]'
gating='[".github/workflows/automerge.yml", ".github/workflows/ci.yml", ".github/workflows/no-comments.yml", ".github/workflows/release.yml", ".github/workflows/auto-release.yml"]'

info=$(cat -- "$info_file" 2>/dev/null) || info=""
files_json=$(cat -- "$files_file" 2>/dev/null) || files_json=""

if ! echo "$info" | jq -er '.headRefOid | select(test("^[0-9a-f]{40}$"))' > /dev/null 2>&1; then
    echo "skip (invalid PR head)"
    exit 0
fi
blocked=$(echo "$info" | jq -r --argjson req "$required" '
  ([.statusCheckRollup[] | select((.name // .context) != "code-review")] as $roll
   | ($req + [$roll[] | .name // .context] | unique) as $names
   | [ $names[] as $r
       | [$roll[] | select((.name // .context) == $r)] as $checks
       | if ($checks | length) == 0
           or any($checks[]; if .__typename == "StatusContext" then .state != "SUCCESS"
                  else .status != "COMPLETED" or .conclusion != "SUCCESS" end)
         then $r else empty end ] )
  | join(",")') || blocked="could not evaluate head checks"
reason=$(echo "$info" | jq -r --arg owner "$REPO_OWNER" '
  if .isCrossRepository != false or .author.login != $owner then "not a same-repo PR by the owner"
  elif .isDraft then "draft"
  elif ([.labels[].name] | index("hold")) then "hold label"
  elif .mergeable != "MERGEABLE" then "not mergeable (\(.mergeable))"
  else "" end') || reason="could not evaluate PR state"
if [ "${reason}" = "null" ]; then reason="could not evaluate PR state"; fi
if [ -z "${reason}" ]; then
    gated=$(echo "${files_json}" | jq -r --argjson gate "$gating" '[.[] | select(. == $gate[])] | length' 2>/dev/null) || gated=""
    if [ -z "${files_json}" ] || ! [ -n "${gated}" ] || ! [ "${gated}" -ge 0 ] 2>/dev/null; then
        reason="could not list PR files"
    elif [ "${gated}" -ge 1 ]; then
        reason="edits a release-gating workflow, needs manual review"
    fi
fi
if [ -n "$blocked" ]; then reason="required checks not green: ${blocked}"; fi
if [ -n "$reason" ]; then echo "skip ($reason)"; exit 0; fi
echo "merge"
