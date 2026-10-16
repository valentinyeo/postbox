import re
import subprocess
import sys

SLASH = {".zig", ".js", ".ts", ".c", ".h", ".cpp"}
HASH = {".py", ".sh", ".ps1"}
SKIP_DIRS = ("vendor/",)
ALLOWED = re.compile(
    r"zig fmt: (off|on)|noqa|shellcheck |type: ignore|pragma|eslint-|trufflehog:ignore|gitleaks:allow|SPDX-License-Identifier"
)


def strip_strings(line, quotes):
    out = []
    i = 0
    quote = None
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in quotes:
            quote = ch
            out.append(" ")
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def comment_in(path, line):
    ext = "." + path.rsplit(".", 1)[-1] if "." in path else ""
    if ext in SLASH:
        if line.lstrip().startswith("\\\\"):
            return None
        code = strip_strings(line, "\"'")
        pos = code.find("/" + "/")
    elif ext in HASH:
        if line.startswith("#!"):
            return None
        code = strip_strings(line, "\"'")
        pos = -1
        for m in re.finditer("#", code):
            prev = code[m.start() - 1] if m.start() else " "
            if prev not in "${<":
                pos = m.start()
                break
    else:
        return None
    if pos < 0:
        return None
    text = line[pos:].strip()
    if ALLOWED.search(text):
        return None
    return text


def added_lines(diff):
    path = None
    lineno = 0
    for raw in diff.splitlines():
        if raw.startswith("+++ "):
            target = raw[4:]
            path = target[2:] if target.startswith("b/") else None
            continue
        if raw.startswith("@@"):
            m = re.search(r"\+(\d+)", raw)
            lineno = int(m.group(1)) if m else 0
            continue
        if path is None or raw.startswith("---"):
            continue
        if raw.startswith("+"):
            yield path, lineno, raw[1:]
            lineno += 1
        elif not raw.startswith("-"):
            lineno += 1


def find_new_comments(diff):
    hits = []
    for path, lineno, line in added_lines(diff):
        if path.startswith(SKIP_DIRS):
            continue
        text = comment_in(path, line)
        if text:
            hits.append((path, lineno, text))
    return hits


def main(argv):
    if len(argv) < 2:
        print("usage: check_new_comments.py <base> [head]")
        return 2
    base = argv[1]
    head = argv[2] if len(argv) > 2 else "HEAD"
    diff = subprocess.run(
        ["git", "diff", "--unified=0", "--no-color", "--diff-filter=AM", f"{base}...{head}"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    hits = find_new_comments(diff)
    for path, lineno, text in hits:
        print(f"{path}:{lineno}: new code comment: {text[:100]}")
    if hits:
        print(f"{len(hits)} new code comment(s). This repo keeps code free of comments: delete them and put the reason in the commit message or PR.")
        return 1
    print("No new code comments.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
