# Gates: IGSH-462 merge and complete chat comparison

OWNS: .github/workflows/verify.yml, src/main.zig, src/text_draw.zig, tools/verify-wazig/**, GATES.md

Scope: Merge origin/main without rebasing, preserve both verify journeys and comparison, prove the missing-row cause and correction, and obtain green GitHub checks plus a new comparison image without local builds or app execution.

- [x] G0: Ledger has valid measurable gates
  CHECK: node /home/valentin/.agents/skills/unlazy/scripts/gate-lint.mjs GATES.md
  EXPECT: LINT OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=69f81179f3934636347ff01de4824d2a1f500f2d29238b9fd688f82f77d1c57b; exit=0; EXPECT=matched; output-sha256=7a7922f0e3f69de36db176b084b74091e068cc8772d7b0d01d49001e587c54e0; output-bytes=150; shell=/bin/sh; cwd=/home/valentin/projects/wazig-IGSH-462; path=b7c9797232e1/20 entries

- [x] G1: Main is merged with a two-parent merge and the branch is pushed without committing this ledger
  CHECK: git merge-base --is-ancestor origin/main HEAD && git log --merges -1 --format='%p' | awk 'NF == 2 { found=1 } END { exit !found }' && test "$(git rev-parse HEAD)" = "$(git rev-parse origin/ceo/IGSH-462-compare)" && test -z "$(git ls-files GATES.md)" && printf 'MERGE AND PUSH VERIFIED\n'
  EXPECT: MERGE AND PUSH VERIFIED
  EVIDENCE: automatic-evidence=v1; definition-sha256=7efe6f4bc771af19ffe2a9cc3b6af84bd4f10a671159f4f063cf6e618c3e3b46; exit=0; EXPECT=matched; output-sha256=198c4139b62bfe31e52ad58c230cd5f8590205c0326ce36d24f70196f49a76ff; output-bytes=24; shell=/bin/sh; cwd=/home/valentin/projects/wazig-IGSH-462; path=b7c9797232e1/20 entries

- [x] G2: Windows desktop-compatible row pixels reproduce the old clipping bug and pass with shape contexts finished before text
  CHECK: gh run view 39703960170 --log > ../ceo/runs/igsh-462/run-39703960170/github-run.log && python3 -c "from pathlib import Path; import re; s=Path('../ceo/runs/igsh-462/run-39703960170/github-run.log').read_text(); assert 'buffered=true name_ink=0 preview_ink=0' in s; assert 'ISSUE-462 OLD RENDERER REJECTED:' in s; after=s.split('ISSUE-462 OLD RENDERER REJECTED:',1)[1]; rows=re.findall(r'row top=(\d+) buffered=true name_ink=(\d+) preview_ink=(\d+)',after); assert {int(r[0]) for r in rows}=={0,64,128,256}; assert all(int(n)>100 and int(p)>20 for _,n,p in rows); assert 'ISSUE-462 ROW TEXT VERIFIED:' in after; print('OLD AND FIXED ROW PIXELS VERIFIED')"
  EXPECT: OLD AND FIXED ROW PIXELS VERIFIED
  EVIDENCE: automatic-evidence=v1; definition-sha256=be8ab909dd8074ee9c9a97b7b356204284803c1bc073f7bd112725cb1bf7230f; exit=0; EXPECT=matched; output-sha256=c939ab08bca58ab53430be6eaf7e8cfb7a737d303e1de7c2599e44988e418ba2; output-bytes=34; shell=/bin/sh; cwd=/home/valentin/projects/wazig-IGSH-462; path=b7c9797232e1/20 entries

- [x] G3: GitHub proves all PR checks pass at the pushed head
  CHECK: gh pr checks 292 && test "$(gh pr view 292 --json headRefOid --jq .headRefOid)" = "$(git rev-parse HEAD)" && printf 'PR HEAD CHECKS VERIFIED\n'
  EXPECT: PR HEAD CHECKS VERIFIED
  EVIDENCE: automatic-evidence=v1; definition-sha256=f072690b06faa1346d674c7d74606bf28606ed91d0cd807946481f04365ef7c8; exit=0; EXPECT=matched; output-sha256=08b1695f8b0341a6d57dfe60b04fafd2b9afb2f3793a421a2e899bed37d1522e; output-bytes=1786; shell=/bin/sh; cwd=/home/valentin/projects/wazig-IGSH-462; path=b7c9797232e1/20 entries

- [x] G4: Successful branch dispatch and downloaded evidence match the pushed head and preserve font and fixture parity
  CHECK: test "$(gh run view 39703960170 --json conclusion --jq .conclusion)" = success && test "$(gh run view 39703960170 --json event --jq .event)" = workflow_dispatch && test "$(gh run view 39703960170 --json headSha --jq .headSha)" = "$(git rev-parse HEAD)" && test "$(jq -r .commit ../ceo/runs/igsh-462/run-39703960170/session.json)" = "$(git rev-parse HEAD)" && cmp ../ceo/runs/igsh-462/text-comparison-2.png ../ceo/runs/igsh-462/run-39703960170/text-comparison.png && node tools/verify-wazig/check-text-comparison.cjs ../ceo/runs/igsh-462/run-39703960170
  EXPECT: ISSUE-462 EVIDENCE VERIFIED:
  EVIDENCE: automatic-evidence=v1; definition-sha256=9b324723640b09ecf81e386857d710ecf55a5c70440cb414f8037f2b35706b51; exit=0; EXPECT=matched; output-sha256=d00d6994297291bc0c11b80850a43d10a2fa4e206e80b8cce2e75e24246b4f3e; output-bytes=166; shell=/bin/sh; cwd=/home/valentin/projects/wazig-IGSH-462; path=b7c9797232e1/20 entries

- [x] G5: New comparison PNG shows both fixture row names and previews painted
  EVIDENCE: Visually inspected /home/valentin/projects/ceo/runs/igsh-462/text-comparison-2.png, SHA256 697542a36df9ce7d54044e4d1d602add3234c0c42060465d9272763e310fc7f7, from successful run 39703960170 at f4a4070671d81751b78d4aa6c4d7c77d63e50415. Both Verification Alpha and Verification Beta names, direct previews, initials and W badges are painted without hover or scroll. Independent PNG pixel read: Alpha name/preview 414/77 bright pixels, Beta 348/76; old repeat Beta 0/0. Hash-bound review recorded in ../ceo/runs/igsh-462/row-review-2.json.

- [x] G6: Changed source has valid syntax and no whitespace errors
  CHECK: git diff --check origin/main...HEAD && node --check tools/verify-wazig/chrome-text.cjs && node --check tools/verify-wazig/check-text-comparison.cjs && node --check tools/verify-wazig/text-comparison.test.cjs && zig ast-check src/main.zig && zig ast-check src/text_draw.zig && printf 'SOURCE SYNTAX VERIFIED\n'
  EXPECT: SOURCE SYNTAX VERIFIED
  EVIDENCE: automatic-evidence=v1; definition-sha256=366db7986a33ccfd4127259594c48c71a80fe57b0465a8452048af0ae639e263; exit=0; EXPECT=matched; output-sha256=25b2ea8639d589e6e47c6f562134dcad96c3bdba67036e1bb716a9adf5357032; output-bytes=23; shell=/bin/sh; cwd=/home/valentin/projects/wazig-IGSH-462; path=b7c9797232e1/20 entries

- [x] G7: Conflict resolution preserves every main journey plus text comparison and passes the Windows map and PowerShell syntax check
  CHECK: python3 -c "import pathlib,re,subprocess; main=subprocess.check_output(['git','show','origin/main:.github/workflows/verify.yml'],text=True); current=pathlib.Path('.github/workflows/verify.yml').read_text(); runner=pathlib.Path('tools/verify-wazig/run.ps1').read_text(); choices=lambda s:set(re.search(r'options: \[([^]]+)\]',s)[1].split(', ')); assert choices(current)==choices(main)|{'text-comparison'}; assert all(chr(39)+v+chr(39) in runner.split('ValidateSet(',1)[1].split(')',1)[0] for v in choices(current)); assert all(v+' {' in runner for v in ['archive','menus','text-comparison']); print('JOURNEY UNION VERIFIED')" && gh run view 39703960170 --json jobs --jq '[.jobs[].steps[] | select(.name == "Check skill map and PowerShell syntax") | .conclusion] | select(length == 1 and all(. == "success")) | "WINDOWS MAP AND SYNTAX VERIFIED"'
  EXPECT: WINDOWS MAP AND SYNTAX VERIFIED
  EVIDENCE: automatic-evidence=v1; definition-sha256=1c66c4c304cd66947f5fccd56734c7f834d0a6cda0e6a8108540b6e2bfc5d563; exit=0; EXPECT=matched; output-sha256=8f94b1dd88a8578023a1f7185db53afb1fd16b33e94b0e424ef5f345247bea0f; output-bytes=55; shell=/bin/sh; cwd=/home/valentin/projects/wazig-IGSH-462; path=b7c9797232e1/20 entries
