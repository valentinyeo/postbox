import argparse
import json
import re
import subprocess
from pathlib import Path


FALLBACK = "Small fixes and speed improvements"


def card_text(body):
    lines = re.findall(r"^Card:[ \t]*(.*)$", body or "", re.MULTILINE)
    if len(lines) != 1:
        raise ValueError("Add exactly one Card: <plain product change> line (or Card: none)")
    text = lines[0].strip()
    if not text or len(text) > 80:
        raise ValueError("Card text must contain 1 to 80 characters")
    if re.search(r"\b[A-Z][A-Z0-9]*-\d+\b|#\d+|\b[\w-]+\.[a-zA-Z][\w]*\b|\w+://|www\.", text, re.IGNORECASE):
        raise ValueError("Card text must not contain ticket ids, PR numbers, file names or URLs")
    return text


def validate(body, files):
    app_changed = any(name.startswith(("src/", "assets/")) for name in files)
    if not app_changed and not re.search(r"^Card:", body or "", re.MULTILINE):
        return
    text = card_text(body)
    if text.lower() == "none" and any(name.startswith("assets/") or name.startswith("src/") and not name.endswith(("_test.zig", "/test.zig")) for name in files):
        raise ValueError("App changes need a product Card line; Card: none is only for tests, tooling, CI or docs")


def release_body(pulls):
    lines = []
    seen = set()
    for pull in sorted(pulls, key=lambda p: p["merged_at"], reverse=True):
        if pull["number"] in seen:
            continue
        seen.add(pull["number"])
        try:
            text = card_text(pull.get("body"))
        except ValueError:
            continue
        if text.lower() != "none":
            lines.append("- " + text)
    return "\n".join(lines or ["- " + FALLBACK]) + "\n"


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def api_pages(endpoint):
    raw = command("gh", "api", "--paginate", endpoint)
    decoder = json.JSONDecoder()
    while raw:
        page, end = decoder.raw_decode(raw)
        yield from page
        raw = raw[end:].lstrip()


def compose_release(repo, tag):
    version = lambda name: tuple(map(int, name[1:].split(".")))
    tags = command("git", "tag", "--merged", tag, "--list", "v*").splitlines()
    previous = [name for name in tags if re.fullmatch(r"v\d+\.\d+\.\d+", name) and version(name) < version(tag)]
    span = max(previous, key=version) + ".." + tag if previous else tag
    commits = set(command("git", "rev-list", span).splitlines())
    pulls = []
    for sha in sorted(commits):
        pulls.extend(pull for pull in api_pages(f"repos/{repo}/commits/{sha}/pulls") if pull.get("merged_at") and pull.get("merge_commit_sha") in commits)
    return release_body(pulls)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="mode", required=True)
    check = sub.add_parser("check")
    check.add_argument("--body-file", required=True)
    check.add_argument("--files", required=True)
    release = sub.add_parser("release-notes")
    release.add_argument("--repo", required=True)
    release.add_argument("--tag", required=True)
    args = parser.parse_args()
    if args.mode == "check":
        try:
            validate(Path(args.body_file).read_text(), Path(args.files).read_text().splitlines())
        except ValueError as error:
            parser.exit(1, str(error) + "\n")
        print("Update card line verified")
    else:
        print(compose_release(args.repo, args.tag), end="")


if __name__ == "__main__":
    main()
