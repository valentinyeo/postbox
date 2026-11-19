---
name: verify-send-queue
description: Formally check the Postbox send queue and voice-note transcription retry with TLA+ models. Use when changing the unified outbox, send retry, restart recovery, or transcription attempts, and when /maintain-formal-verification-skill asks whether the models still match the code.
---

pstack: 0.15.43

Prior art: checked pstack create-formal-verification-skill, maintain-formal-verification-skill and verification-check. This is the project-local skill that create-formal-verification-skill generates, so it adds only Postbox's models, run command and coverage record.

# Verify the send queue and transcription retry

## What this proves

- A queued message is never silently lost. It is delivered, still queued, or deleted by the user.
- An automatic retry never makes the hub accept the same send twice, as long as the hub dedupes by the saved client id.
- Automatic sends stop after four tries and the record is then held.
- Only one send is in flight at a time.
- A voice note is sent for transcription at most once per chat open, even after a reload.
- A finished transcript is never requested again.

## Tool and why

TLA+ with the TLC model checker, version 2.19 from `tla2tools.jar` v1.7.4. The jar is pinned by sha256 in `tools/formal/check_formal.py` and downloaded on first run. TLA+ fits because the risk is event order: crash, lost result, retry and user action interleave. TLC runs on the laptop in under a minute and needs only Java. It is a focused check, not the full test suite.

## Run it

One command from the repo root:

```
python3 tools/formal/check_formal.py --tlc
```

It first compares every covered function with the hashes in `tools/formal/coverage.json`. Any `DRIFT` line means the code changed since the models were last confirmed. Then it runs each model and each broken variant. Every line must start with `PASS`.

- `--only send-queue` or `--only transcribe-retry` runs one model.
- `--only <variant name>` runs one broken variant.
- `--trace` prints the full checker output, including any counterexample.

## Read results

Read every TLC result with the pstack `/statechart` skill. It shows each broken property as its shortest path in plain words. Report a finding as a counterexample in code terms: name the function and the event order. Never weaken a property to make a run pass. Never change product code unless asked.

## Models

- `tools/formal/send-queue/SendQueue.tla`. Per message: ready, uncertain, held, acked, deleted. Events: dispatch, network result, commit of the result, crash, user retry, user delete. Bounds: 2 messages, 1 crash, 1 user retry id, 4 sends.
- `tools/formal/transcribe-retry/TranscribeRetry.tla`. Per voice note: none, loading, ready, failed. Events: chat open, message reload, start, finish. Bounds: 3 notes, attempt list of 2, 2 opens, 2 reloads.

Each constant at the top of a `.cfg` file switches one behaviour. A broken variant flips one constant and must break exactly the named property. These are the proof that the properties can fail:

| Variant | Flips | Must break |
|---|---|---|
| hub-does-not-dedupe | the hub accepts a repeated id twice | NoDouble |
| retry-mints-fresh-id | an automatic retry uses a new id | NoDouble |
| ack-on-ambiguous-result | an unclear result is treated as delivered | NoLoss |
| drop-record-on-give-up | the record is deleted after the last try | NoLoss |
| retry-without-attempt-bound | retries never stop | AutoSendsBounded |
| dispatch-while-inflight | a second send starts during one | SingleInflight |
| attempt-not-recorded | the attempt list is not written | OneRequestPerOpen |
| reopen-clears-ready | a finished transcript is forgotten | NeverRerequestReady |
| parallel-requests | two transcriptions at once | OneAtATime |

## Findings

- The no-double-send property holds only if the hub dedupes by the saved client id. The variant `hub-does-not-dedupe` breaks it. The real hub behaviour is proven by the `hub-send-dedupe` journey in `verify-wazig`, not by the model.
- A user retry mints a new id by design. After an unclear result it can deliver twice. The model exempts it from NoDouble on purpose.
- No counterexample was found for the other properties inside the bounds.

## Not covered

- The 64-entry outbox limit and its eviction.
- Slack, Telegram and Signal transport details.
- The delay values and real time. The models only keep the bound of four sends.
- File format and disk write failures beyond a result that is not yet saved.
- Dictation recording, and the cloud service's own behaviour.
- The Zig code itself. The models describe it. They do not compile or run it.

## Keep it in sync

`tools/formal/coverage.json` records the sync commit and a hash of each covered function. When `check_formal.py` prints `DRIFT`, run `/pstack:maintain-formal-verification-skill`: read the changed function, update the model if its behaviour changed, rerun `--tlc`, then record the new hashes with `python3 tools/formal/check_formal.py --update <commit>`. A drift that needs no model change still needs that record, so the next agent knows someone looked.
