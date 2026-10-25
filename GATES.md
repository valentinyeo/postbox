# Gates: IGSH-823 background-independent full-strength check

OWNS: GATES.md, tools/test_show_archived.py, tools/verify-wazig/check-archive-presentation.py

Scope: Replace the full-strength contrast comparison with rounded text luminance, retain the live contrast floor and unchanged dim-branch checks, prove positive and mutation fixtures, then create and push a new commit on ceo/IGSH-823.

Authorization: The only local test command is `python3 tools/test_show_archived.py`; checker help inspection is also permitted. No separate gate checker, linter, build or other test command will run. Evidence is direct test output and source/Git review, not automatic gate-checker certification. Git inspection, commit and push are explicitly requested. Earlier ledger results do not certify this change.

- [x] G1: Full-strength rows use rounded weighted RGB text luminance, require archived_mean >= live_mean - 8, and retain the live contrast floor of 4.5; the dim branch still requires mix error <= 8, 0 < contrast-excess ratio < 1 and colour distance > 15.
  EVIDENCE: Reviewed tools/verify-wazig/check-archive-presentation.py:32-44 and :71-95. The measured text pixels retain the existing contrast > 1.5 text/background separation and minimum count of 24. Their mean uses 0.2126*R + 0.7152*G + 0.0722*B, rounded after averaging. Each row records its own mean. Full-strength mode requires archived mean >= live mean - 8; light-background black-text fixtures additionally require archived mean <= live mean + 8 because dimming increases raw luminance there. The live contrast floor and every dim-branch assertion are unchanged.

- [x] G2: Full-strength hover/selection accepts different row backgrounds and ClearType channel differences, while dimmed hover/selection fails before saved-metric comparison; existing dark/light and dim-branch controls pass.
  CHECK: python3 tools/test_show_archived.py
  EXPECT: (?m)^OK(?: \(skipped=\d+\))?$
  EVIDENCE: Direct execution from /home/valentin/projects/wazig-wt/IGSH-823 exited 0: Ran 15 tests in 51.515s; OK (skipped=1). The existing shortcut-history test skips because HEAD~1 already contains Alt+A. New fixtures cover sidebar/search/inbox hover and selection with live background black and archived background #262626: live contrast 21.000000 versus archived 15.133529 is accepted with both means 255. Mixed text means 247 pass, 246 fail, and 180 fail despite representative brightest text remaining white. Failures invoke capture=True and require the dimmed-interaction message, not stale metrics. Existing uniform dimmed dark/light interactions also fail. ClearType RGB channel differences of 22 retain rounded means 253 (dark) and 2 (light) and pass. Complete evidence dispatch and existing dim-mix/model, footer and source controls pass. These are synthetic fixtures, not Windows app measurements.

- [x] G3: Only the owned files change and no code comments are introduced.
  EVIDENCE: Initial git status was clean on ceo/IGSH-823 at a05bf3bc51d153853295435739db2a569e8157c2. Reviewed the full code diff after the passing suite: only tools/test_show_archived.py and tools/verify-wazig/check-archive-presentation.py change besides this ledger. No comments were added; the authorized suite's existing no-code-comments test passed. No application rendering or dim-branch behavior changed.

Verification ledger: 3 met, 0 unmet, 0 abandoned. Delivery follows verification: create a new commit without amending, push origin ceo/IGSH-823, and report the independently inspected final HEAD and push outcome outside this immutable commit's ledger.
