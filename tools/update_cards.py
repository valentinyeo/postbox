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


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def api_pages(endpoint):
    raw = command("gh", "api", "--paginate", endpoint)
    decoder = json.JSONDecoder()
    while raw:
        page, end = decoder.raw_decode(raw)
        yield from page
        raw = raw[end:].lstrip()


def card_from_subject(subject):
    text = re.sub(r"^\s*[A-Z][A-Z0-9]*-\d+:\s*", "", subject or "").strip()
    if not text or len(text) > 80:
        return None
    if re.search(r"\b(ci|tests?|tooling|workflow|verify|journeys?|lint|harness|compil\w*|build|renderer|module|layer|helper|refactor)\b", text, re.IGNORECASE):
        return None
    if re.search(r"\b[A-Z][A-Z0-9]*-\d+\b|#\d+|\b[\w-]+\.[a-zA-Z][\w]*\b|\w+://|www\.", text, re.IGNORECASE):
        return None
    return text


def app_files(sha):
    listing = command("git", "show", "--name-only", "--format=", sha)
    return [line.strip() for line in listing.splitlines() if line.strip()]


def commit_product_text(sha):
    changed = [name for name in app_files(sha) if name.startswith(("src/", "assets/")) and not name.endswith(("_test.zig", "/test.zig"))]
    if not changed:
        return None
    return card_from_subject(command("git", "log", "-1", "--format=%s", sha))


def compose_release(repo, tag):
    version = lambda name: tuple(map(int, name[1:].split(".")))
    tags = command("git", "tag", "--merged", tag, "--list", "v*").splitlines()
    previous = [name for name in tags if re.fullmatch(r"v\d+\.\d+\.\d+", name) and version(name) < version(tag)]
    span = max(previous, key=version) + ".." + tag if previous else tag
    commits = command("git", "rev-list", span).splitlines()
    bullets = []
    seen = set()
    for sha in commits:
        text = None
        for pull in api_pages(f"repos/{repo}/commits/{sha}/pulls"):
            if not pull.get("merged_at") or pull.get("merge_commit_sha") != sha:
                continue
            try:
                candidate = card_text(pull.get("body"))
            except ValueError:
                continue
            if candidate.lower() != "none":
                text = candidate
                break
        if text is None:
            text = commit_product_text(sha)
        if not text or text in seen:
            continue
        seen.add(text)
        bullets.append("- " + text)
    return "\n".join(bullets[:12] or ["- " + FALLBACK]) + "\n"


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
