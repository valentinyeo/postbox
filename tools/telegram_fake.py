import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ("login", "list", "history", "send", "send_file", "reply", "live", "inbox")


def extract(source, name):
    start = source.index(f"fn {name}(")
    return source[start:source.index("\n}\n", start) + 3]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", action="store_true")
    args = parser.parse_args()

    def source(name):
        if args.baseline:
            return subprocess.check_output(["git", "show", f"origin/main:src/{name}"], cwd=ROOT).decode()
        return (ROOT / "src" / name).read_text()

    (ROOT / ".zig-cache").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="telegram-fake-", dir=ROOT / ".zig-cache") as temporary:
        directory = Path(temporary)
        for name in ("telegram.zig", "telegram_json.zig", "transport.zig", "chat_key.zig", "messenger_view.zig", "archive_rules.zig"):
            (directory / name).write_text(source(name))
        production = source("main.zig")
        names = ("WideText", "Utf8Text", "tgChatIdString", "selectedChatIsTelegram", "tgSelectedChatId", "tgSelectedChatIsGroup", "upsertTgChat", "appendTelegramChats", "refreshTelegramMessages", "tgDisplayText", "telegramAutoDownload", "discardStagedImage", "releaseStagedImage")
        sections = [extract(production, name) for name in names]
        if "fn chatInView(" in production:
            sections.append(extract(production, "chatInView"))
        if "fn stageFile(" in production:
            sections.append(extract(production, "stageFile"))
        for name in ("Chat", "TgChat", "StagedImage"):
            sections.append(re.search(rf"^const {name} = struct \{{.*?^}};", production, re.M | re.S).group())
        sections.append(re.search(r"^const max_tg_chats = .*?;", production, re.M).group())
        sending = extract(production, "sendMessage")
        start = sending.index("    if (selectedChatIsTelegram(a)) {")
        end = sending.index("    if (selectedChatIsSlack(a)) {", start)
        sections.append("fn sendTelegram(a: *App, text: []const u8, staged_file: []const u8) void {\nstd.mem.doNotOptimizeAway(staged_file);\n" + sending[start:end] + "}\n")
        fixture = (ROOT / "tools/telegram_fake.zig").read_text()
        (directory / "test.zig").write_text(fixture + "\n" + "\n".join(sections))
        command = [os.environ["ZIG"], "test", str(directory / "test.zig"), str(ROOT / "tools/telegram_fake.c"), "-lc", "--test-filter", "fake "]
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print(result.stdout, end="")
        passed = re.findall(r"^TG_FAKE_OK (\w+)$", result.stdout, re.M)
        if result.returncode or passed != list(SCENARIOS):
            raise SystemExit(result.returncode or 1)


if __name__ == "__main__":
    main()
