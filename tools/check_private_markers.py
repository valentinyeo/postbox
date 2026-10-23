import os
import re
import subprocess
import sys

SKIP_DIRS = ("vendor/",)
PRIVATE_PATHS = ("CLAUDE.local.md", "HANDOFF.md", "board.yml", ".claude/skills/", ".claude/hooks/agent-scope-guard.sh", ".claude/handoffs/")

PUBLIC_SKILL_PATHS = (
    ".claude/skills/verify-wazig/features/paste-image.md",
    ".claude/skills/verify-wazig/features/hub-archive.md",
    ".claude/skills/verify-wazig/features/palette-archived.md",
    ".claude/skills/verify-wazig/features/reactions.md",
    ".claude/skills/verify-wazig/SKILL.md",
    ".claude/skills/verify-wazig/INDEX.md",
    ".claude/skills/verify-wazig/RULE-MAP.md",
    ".claude/skills/verify-wazig/features/notrap.md",
    ".claude/skills/verify-wazig/features/signal.md",
    ".claude/skills/verify-wazig/features/telegram.md",
    ".claude/skills/verify-wazig/features/README.md",
    ".claude/skills/verify-wazig/features/search.md",
    ".claude/skills/verify-wazig/features/navigation.md",
    ".claude/skills/verify-wazig/features/drafts.md",
    ".claude/skills/verify-wazig/features/palette.md",
    ".claude/skills/verify-wazig/features/appearance.md",
    ".claude/skills/verify-wazig/features/whatsapp-hub.md",
    ".claude/skills/verify-wazig/features/hub.md",
    ".claude/skills/verify-wazig/features/slack-sort.md",
    ".claude/skills/verify-wazig/features/slack-archive.md",

    ".claude/skills/verify-wazig/features/slack-threads.md",
    ".claude/skills/verify-wazig/features/workspace-icons.md",
    ".claude/skills/verify-wazig/features/menus.md",
    ".claude/skills/verify-wazig/features/archive.md",
    ".claude/skills/verify-wazig/features/views.md",
    ".claude/skills/verify-wazig/features/window.md",
    ".claude/skills/verify-wazig/features/repaint.md",
    ".claude/skills/verify-wazig/features/voice.md",
)


def load_markers(text):
    return [re.compile(line.strip()) for line in text.splitlines() if line.strip()]


def scan_text(label, text, markers):
    hits = []
    for number, line in enumerate(text.splitlines(), 1):
        for index, marker in enumerate(markers, 1):
            if marker.search(line):
                hits.append((label, number, index))
    return hits


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, check=True).stdout


def readable(data):
    if b"\0" in data[:8000]:
        return None
    return data.decode("utf-8", "replace")


def private_paths(paths):
    return [path for path in paths if (path == ".claude/skills" or path.startswith(PRIVATE_PATHS)) and path not in PUBLIC_SKILL_PATHS]


def scan_tree(markers):
    hits = []
    paths = git("ls-files", "-z").decode().split("\0")
    for path in private_paths(paths):
        hits.append((path, 0, 0))
    for path in paths:
        if not path or path.startswith(SKIP_DIRS) or not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            text = readable(handle.read())
        if text is not None:
            hits += scan_text(path, text, markers)
    return hits


def scan_logs(markers, directory):
    hits = []
    for root, dirs, files in os.walk(directory):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            with open(path, "rb") as handle:
                text = readable(handle.read())
            if text is not None:
                hits += scan_text(os.path.relpath(path, directory), text, markers)
    return hits


def scan_history(markers):
    hits = []
    seen = set()
    for line in git("rev-list", "--all", "--objects").decode().splitlines():
        sha, _, path = line.partition(" ")
        if not path or path.startswith(SKIP_DIRS) or sha in seen:
            continue
        seen.add(sha)
        if git("cat-file", "-t", sha).strip() != b"blob":
            continue
        text = readable(git("cat-file", "blob", sha))
        if text is not None:
            hits += scan_text(f"{path}@{sha[:10]}", text, markers)
    hits += scan_text("commit messages", git("log", "--all", "--format=%B").decode("utf-8", "replace"), markers)
    return hits


def scan_pr(markers, base, head):
    hits = scan_text("PR title", os.environ.get("PR_TITLE", ""), markers)
    hits += scan_text("PR body", os.environ.get("PR_BODY", ""), markers)
    log = git("log", "--format=%H%n%B", f"{base}..{head}").decode("utf-8", "replace")
    hits += scan_text("PR commit messages", log, markers)
    return hits


def main(argv):
    markers = load_markers(os.environ.get("PRIVATE_MARKERS", ""))
    if not markers:
        print("PRIVATE_MARKERS is empty: set the repo secret from the private companion repo. Refusing to pass.")
        return 2
    if argv[:1] == ["--logs"]:
        if len(argv) != 2 or not os.path.isdir(argv[1]):
            print("usage: check_private_markers.py --logs <directory>")
            return 2
        hits = scan_logs(markers, argv[1])
    elif argv[:1] == ["--history"]:
        hits = scan_history(markers)
    else:
        hits = scan_tree(markers)
        if len(argv) == 2:
            hits += scan_pr(markers, argv[0], argv[1])
    for label, number, index in hits:
        if index == 0:
            print(f"{label}: private agent file is tracked. It belongs in the private companion repo; tools/agent-setup.sh links it in.")
        else:
            print(f"{label}:{number}: private marker #{index}. Move this to the private companion repo or reword it.")
    if hits:
        return 1
    print(f"No private markers ({len(markers)} checked).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
