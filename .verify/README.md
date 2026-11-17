# Postbox gate adoption

Adoption remains blocked. Do not merge yet.

The shared gate supports Python and JavaScript only.
Postbox uses native Zig and Win32.
Configuration names the missing Zig adapter explicitly.
No application source is excluded to force green.
The JavaScript adapter cannot solve this mismatch.

The source inventory uses actual application code.
Its helper finds bounded registration and handler patterns.
It cannot certify every custom Win32 entry point.
Full semantic coverage remains an adoption blocker.
Removing a detected entry fails the inventory check.
The shared gate fails earlier, on unsupported Zig.
Those failures must never be conflated.

The workflow pin matches the reviewed upstream revision.
Existing desktop verification moves to `verify-desktop.yml`.
The original workflow name and journey registry remain.
The canonical `verify.yml` calls the shared gate.

Policy must enter the trusted base separately.
The collector rejects this PR's self-supplied policy.
The verifier registry therefore starts empty.
Do not register a human as verifier.
Register the actual different-family agent and workflow.
Current-head evidence must come from hosted Actions.

Both release workflows still need blocking verification dependencies.
Branch protection must require the emitted gate statuses.
No repository setting changes happen in this PR.
The `hold` label prevents the existing automatic merger.
Nothing here earns automatic merging or publishing.

Private production data stays outside Git.
Configuration records known limits and fixture sizes.
Installed profile counts remain unknown.
The verifier must measure them without exposing content.

Missing release proof includes current-head video or trace.
It also includes the digested Actions evidence manifest.
No release proof is fabricated during adoption.
