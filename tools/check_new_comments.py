import argparse
from pathlib import Path
import subprocess


parser = argparse.ArgumentParser(description="Enforce the repository's no-code-comments policy")
parser.add_argument("base", nargs="?", default="origin/main")
args = parser.parse_args()
subprocess.run(["git", "rev-parse", "--verify", args.base + "^{commit}"], check=True, stdout=subprocess.DEVNULL)
raise SystemExit(subprocess.run(["node", str(Path(__file__).with_name("strip-comments.mjs")), "--check"]).returncode)
