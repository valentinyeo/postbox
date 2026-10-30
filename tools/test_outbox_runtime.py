import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FUNCTIONS = (
    "stagedFileGoesToWacli", "persistOutbox", "writeOutboxAtomic", "loadOutbox", "bindOutboxAccount", "enqueueSlackOutbox", "retrySlackOutbox",
    "retireSlackOutbox", "evictOldestFailedSlackOutbox", "completePendingSend", "removeFirstPendingSend", "sendMessage", "sendMessageFrom",
    "resolveSlackSend", "pendingByClientMsgId", "jobIsWrite", "jobIsSlack",
    "wacliEnqueue", "wacliTakeJob", "wacliJobArgs", "storedAfterQueued", "sentMessageExists", "startNextSend", "retryWacliRefreshes", "appendWhatsAppPending", "retryingBubbleText", "localSendId", "replySnippet", "setReplyQuote", "failHeadPendingSend", "sendRetryDelayMs", "markPendingSendFailed", "markPendingSendRetrying", "sendBaseText", "sendKindName", "applyHubResult",
)


def extract(source, name):
    start = source.index(f"fn {name}(")
    end = source.index("\n}\n", start) + 3
    body = source[start:end]
    if name == "applyHubResult":
        begin = body.index("        .hub_send => {")
        end = body.index("        .hub_read =>", begin)
        body = "fn applyHubResult(a: *App, result: *const WacliResult) void {\n    switch (result.kind) {\n" + body[begin:end] + "        else => {},\n    }\n}\n"
    if name == "startNextSend":
        body = body[:body.index("    const pending = &a.pending_sends[0];")] + "    spawned += 1;\n}\n"
    return body


def mutate(source, name):
    if name in ("short-job-args", "nul-field", "negative-time", "evict-write"):
        return source
    replacements = {
        "ignored-swap": ("return win.MoveFileExW(wide.ptr, target.ptr, win.MOVEFILE_REPLACE_EXISTING | win.MOVEFILE_WRITE_THROUGH) != 0;", "_ = win.MoveFileExW(wide.ptr, target.ptr, win.MOVEFILE_REPLACE_EXISTING | win.MOVEFILE_WRITE_THROUGH); return true;"),
        "unflushed-write": ("win.FlushFileBuffers(handle) != 0", "true"),
        "local-zero": ("a.send_seq += 1;\n            pending.seq = a.send_seq;", "pending.seq = 0;"),
        "no-credentials": ("or !slackConfigured(a) ", ""),
        "wrong-retirement": ("if (!std.mem.eql(u8, slot.entry.idSlice(), id)) continue;", "_ = id;"),
        "wrong-failed-bubble": ("const index = pendingByClientMsgId(a, client_msg_id) orelse return;", "const index = if (!result.ok) oldestPendingSend(a) orelse return else pendingByClientMsgId(a, client_msg_id) orelse return;"),
        "slack-paste-to-whatsapp": ("staged_file.len > 0 and (unifiedHub(a) or stagedFileGoesToWacli(a.chats[a.selected_chat].provider))", "staged_file.len > 0"),
        "same-text-reload": ("if (!unifiedHub(a) and (head.from_disk or (head.retries > 0 and head.ambiguous)) and", "if (!unifiedHub(a) and (head.from_disk or head.retries == 0 or (head.retries > 0 and head.ambiguous)) and"),
        "restored-resend": ("if (!unifiedHub(a) and (head.from_disk or (head.retries > 0 and head.ambiguous)) and", "if (!unifiedHub(a) and head.retries > 0 and head.ambiguous and"),
        "delete-before-retirement": ("if (!persistOutbox(a)) {\n        setStatus(a, \"Could not save send completion; retrying journal\");\n        return false;\n    }", "_ = persistOutbox(a);"),
        "silent-admission": ("if (!persistOutbox(a)) {\n        a.pending_send_count -= 1;\n        pending.* = .{};\n        setStatus(a, \"Could not save outbox; message not queued\");\n        return;\n    }", "_ = persistOutbox(a);"),
        "utf8-truncation": ("if (text.len > outbox.max_text_len)", "if (false)"),
        "hidden-restored-bubble": ("if (!unifiedHub(a) and from_reload and !pending.from_disk)", "if (!unifiedHub(a) and from_reload)"),
        "voice-metadata": ("entry.ptt = pending.ptt;", "entry.ptt = false;"),
        "reaction-eviction": (".reaction, .slack_send, .slack_attach, .slack_share => true,", ".slack_send, .slack_attach, .slack_share => true,"),
        "lost-refresh": ("if (!jobIsWrite(job.kind)) a.wacli_refresh_again = true;", ""),
        "no-account-migration": ("if (pending.provider == .whatsapp and (pending.account.len == 0 or", "if (false and (pending.account.len == 0 or"),
        "overwrite-known-account": ("pending.provider == .whatsapp and (pending.account.len == 0 or", "pending.provider == .whatsapp and (true or"),
        "send-wrong-account": ("or (!unifiedHub(a) and !std.mem.eql(u8, head.account.slice(), a.cache_tag.slice()))", ""),
        "jid-only-dedup": ("if (!chat_key.Key.eql(chat_key.of(&a.chats[a.selected_chat]), key) or !chat_key.Key.eql(chat_key.displayed(a), key)) return false;", "if (!std.mem.eql(u8, a.chats[a.selected_chat].jid.slice(), key.id)) return false;"),
        "partial-load": ("if (win.ReadFile(handle, buffer[total..].ptr, @intCast(buffer.len - total), &got, null) == 0) return;", "if (win.ReadFile(handle, buffer[total..].ptr, @intCast(buffer.len - total), &got, null) == 0) break;"),
    }
    if name == "inline-slack-network":
        old = re.search(r'if \(jobIsSlack\(job.kind\) and a.wacli_slack_thread == null\) \{\n        setStatus\(a, "[^"\n]*"\);\n        return false;\n    }', source).group()
        return source.replace(old, "", 1)
    if name == "overtake-refused":
        old = re.search(r"    for \(a.slack_outbox\[0\.\.a.slack_outbox_count\]\) \|\*earlier\| \{.*?\n    }", source, re.S).group()
        return source.replace(old, "", 1)
    old, new = replacements[name]
    assert old in source, name
    return source.replace(old, new, 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zig", required=True)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    source = (ROOT / "src/main.zig").read_text()
    bodies = "\n\n".join(extract(source, name) for name in FUNCTIONS)
    fixture = (ROOT / "tools/outbox_runtime_test.zig").read_text()
    for name in ("max_pending_sends", "max_slack_outbox", "max_wacli_args", "wacli_arg_cap", "wacli_queue_size"):
        declaration = re.search(rf"^const {name} = .*?;", source, re.M).group()
        fixture = re.sub(rf"^const {name} = .*?;", lambda _: declaration, fixture, flags=re.M)
    declaration = re.search(r"^const WacliJobKind = enum\(u8\) \{.*?};", source, re.M | re.S).group()
    fixture = re.sub(r"^const WacliJobKind = enum\(u8\) \{.*?};", lambda _: declaration, fixture, flags=re.M | re.S)
    for name in ("PendingSend", "SlackOutbox", "WacliJob", "WacliResult"):
        pattern = rf"^const {name} = struct \{{.*?^}};"
        declaration = re.search(pattern, source, re.M | re.S).group()
        fixture = re.sub(pattern, lambda _: declaration, fixture, flags=re.M | re.S)
    mutants = [None]
    if args.negative_controls:
        mutants += ["inline-slack-network", "ignored-swap", "unflushed-write", "local-zero", "no-credentials",
                    "wrong-retirement", "wrong-failed-bubble", "slack-paste-to-whatsapp",
                    "same-text-reload", "restored-resend", "delete-before-retirement", "silent-admission",
                    "utf8-truncation", "partial-load", "overtake-refused", "short-job-args",
                    "nul-field", "negative-time", "lost-refresh", "evict-write", "hidden-restored-bubble", "voice-metadata", "reaction-eviction", "no-account-migration", "overwrite-known-account", "send-wrong-account", "jid-only-dedup"]
    (ROOT / ".zig-cache").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="outbox-runtime-", dir=ROOT / ".zig-cache") as directory:
        directory = Path(directory)
        (directory / "chat_key.zig").write_text((ROOT / "src/chat_key.zig").read_text())
        (directory / "transport.zig").write_text((ROOT / "src/transport.zig").read_text())
        (directory / "voice_sent.zig").write_text((ROOT / "src/voice_sent.zig").read_text())
        (directory / "staged_images.zig").write_text((ROOT / "src/staged_images.zig").read_text())
        format_source = (ROOT / "src/outbox.zig").read_text()
        for mutant in mutants:
            effective_format = format_source
            if mutant == "nul-field":
                effective_format = effective_format.replace("if (std.mem.indexOfScalar(u8, field, 0) != null) return error.InvalidEntry;", "_ = field;")
            if mutant == "evict-write":
                effective_format = effective_format.replace("if (!keep[index]) return index;", "_ = keep[index]; return index;")
            if mutant == "negative-time":
                effective_format = effective_format.replace("if (value.queued_unix < 0) return error.InvalidEntry;", "")
            (directory / "outbox.zig").write_text(effective_format)
            production = bodies if mutant is None else mutate(bodies, mutant)
            effective_fixture = fixture.replace("const wacli_arg_cap = 4095;", "const wacli_arg_cap = 512;") if mutant == "short-job-args" else fixture
            (directory / "test.zig").write_text(effective_fixture + "\n" + production)
            run = subprocess.run([args.zig, "test", str(directory / "test.zig")], cwd=ROOT,
                                 text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if mutant is None:
                print(run.stdout, end="")
                if run.returncode:
                    raise SystemExit(run.returncode)
            else:
                if run.returncode == 0 or "FAIL (Test" not in run.stdout:
                    print(run.stdout, end="")
                    raise SystemExit(f"Negative control {mutant} did not fail a runtime assertion")
                failures = [line for line in run.stdout.splitlines() if "FAIL (Test" in line]
                print(f"NEGATIVE CONTROL {mutant}: " + "; ".join(failures))
    print("OUTBOX_RUNTIME_VERIFIED")


if __name__ == "__main__":
    main()
