import pathlib
import re
import sys

KEY = re.compile(r"^\s*key:\s*(.*)$")
HASHED = re.compile(r"hashFiles\(([^)]*)\)")


def problems(name, text):
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        m = KEY.match(line)
        if not m:
            continue
        for args in HASHED.findall(m.group(1)):
            if ".github/workflows" in args:
                out.append(f"{name}:{n}: cache key hashes a workflow file ({args.strip()}); hash only the files that build the cached output")
    return out


def main(root):
    found = []
    for path in sorted(pathlib.Path(root, ".github", "workflows").glob("*.y*ml")):
        found += problems(str(path.relative_to(root)), path.read_text())
    for p in found:
        print(p, file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
