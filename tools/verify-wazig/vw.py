#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
WORKFLOW = "verify.yml"
READ_ONLY_CTL = {"status", "chats", "messages", "help", "--help", "-h"}


class CliError(Exception):
    def __init__(self, message, next_step, code=2):
        super().__init__(message)
        self.message = message
        self.next_step = next_step
        self.code = code


def emit(value):
    json.dump(value, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def load_journeys():
    path = HERE / "journeys.json"
    try:
        return json.loads(path.read_text(encoding="utf-8"))["journeys"]
    except (OSError, ValueError, KeyError) as error:
        raise CliError(f"cannot read {path.name}: {error}", "Run from a full checkout of the repository.")


def find_journey(feature):
    journeys = load_journeys()
    for journey in journeys:
        if journey["name"] == feature:
            return journey
    names = ", ".join(sorted(j["name"] for j in journeys))
    raise CliError(f"unknown journey '{feature}'", f"Pick one of: {names}. Run `vw.py journeys` for the list.")


def planted_files(feature):
    base = HERE / "planted"
    return {suffix: (base / f"{feature}.{suffix}").is_file() for suffix in ("patch", "txt", "check")}


def tool_path(name, env_name):
    override = os.environ.get(env_name)
    if override:
        return override
    found = shutil.which(name)
    if not found:
        raise CliError(f"{name} is not installed on this machine", f"Install {name} or set {env_name} to its full path.", 3)
    return found


def run_and_pass_through(command, dry_run, extra=None):
    plan = {"command": command, "dry_run": dry_run}
    if extra:
        plan.update(extra)
    if dry_run:
        emit(plan)
        return 0
    return subprocess.run(command, cwd=ROOT).returncode


def gh_json(args):
    gh = tool_path("gh", "VW_GH")
    result = subprocess.run([gh, *args], capture_output=True, text=True, cwd=ROOT)
    if result.returncode != 0:
        raise CliError(
            f"gh {' '.join(args[:2])} failed: {result.stderr.strip() or result.stdout.strip()}",
            "Run `gh auth status` and check the run id and repository.",
            result.returncode,
        )
    return result.stdout


def cmd_journeys(args):
    rows = []
    for journey in load_journeys():
        planted = planted_files(journey["name"])
        rows.append(
            {
                "name": journey["name"],
                "runs_on_pull_requests": bool(journey.get("pr")),
                "script": journey.get("script"),
                "has_planted_bug": planted["patch"] and planted["check"],
            }
        )
    emit({"count": len(rows), "journeys": rows})
    return 0


def cmd_describe(args):
    journey = find_journey(args.feature)
    planted = planted_files(args.feature)
    emit({"journey": journey, "planted_files": planted})
    return 0


def cmd_run(args):
    find_journey(args.feature)
    if args.repeat not in (1, 2, 3):
        raise CliError("repeat must be 1, 2 or 3", "Pass --repeat 1, --repeat 2 or --repeat 3.")
    command = ["gh", "workflow", "run", WORKFLOW, "-f", f"feature={args.feature}", "-f", f"repeat={args.repeat}"]
    if args.ref:
        command += ["--ref", args.ref]
    if args.dry_run:
        emit({"command": command, "dry_run": True})
        return 0
    command[0] = tool_path("gh", "VW_GH")
    result = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
    if result.returncode != 0:
        raise CliError(
            f"dispatch failed: {result.stderr.strip()}",
            f"Check that {WORKFLOW} exists on the default branch and `gh auth status` passes.",
            result.returncode,
        )
    emit({"dispatched": True, "feature": args.feature, "repeat": args.repeat, "next": f"vw.py runs --feature {args.feature}"})
    return 0


def cmd_runs(args):
    out = gh_json(["run", "list", "--workflow", WORKFLOW, "--limit", str(args.limit), "--json", "databaseId,status,conclusion,headBranch,displayTitle,url"])
    runs = json.loads(out)
    if args.feature:
        runs = [run for run in runs if args.feature in run.get("displayTitle", "")]
    emit({"runs": runs})
    return 0


def cmd_status(args):
    out = gh_json(["run", "view", str(args.run_id), "--json", "status,conclusion,url,jobs"])
    data = json.loads(out)
    jobs = [{"name": job["name"], "status": job["status"], "conclusion": job["conclusion"]} for job in data["jobs"]]
    counts = {}
    for job in jobs:
        key = job["conclusion"] or job["status"]
        counts[key] = counts.get(key, 0) + 1
    emit({"run": args.run_id, "status": data["status"], "conclusion": data["conclusion"], "url": data["url"], "job_counts": counts, "jobs": jobs})
    return 0


def cmd_evidence(args):
    find_journey(args.feature)
    destination = args.dir or f"evidence/{args.run_id}"
    command = ["gh", "run", "download", str(args.run_id), "--name", f"verify-wazig-{args.feature}", "--dir", destination]
    if args.dry_run:
        emit({"command": command, "dry_run": True})
        return 0
    command[0] = tool_path("gh", "VW_GH")
    result = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
    if result.returncode != 0:
        raise CliError(
            f"download failed: {result.stderr.strip()}",
            f"Check that run {args.run_id} finished and uploaded verify-wazig-{args.feature}.",
            result.returncode,
        )
    emit({"downloaded": destination})
    return 0


def cmd_drive(args):
    find_journey(args.feature)
    command = [
        "pwsh", "-NoProfile", "-File", str(HERE / "run.ps1"),
        "-Feature", args.feature, "-Bin", args.bin, "-Evidence", args.evidence,
    ]
    if args.expected_version:
        command += ["-ExpectedVersion", args.expected_version]
    if not args.dry_run:
        command[0] = tool_path("pwsh", "VW_PWSH")
    return run_and_pass_through(command, args.dry_run, {"feature": args.feature})


def cmd_ctl(args):
    if not args.ctl_args:
        raise CliError("ctl needs a wazigctl command", "Try `vw.py ctl --bin zig-out/bin -- status`.")
    mutating = args.ctl_args[0] not in READ_ONLY_CTL
    exe = Path(args.bin) / "wazigctl.exe"
    command = [str(exe), *args.ctl_args]
    if mutating and not args.dry_run and not args.allow_write:
        raise CliError(
            f"'{args.ctl_args[0]}' can change app state",
            "Preview it with --dry-run, then rerun with --allow-write.",
        )
    if not args.dry_run and not exe.is_file():
        raise CliError(f"{exe} does not exist", "Build it with `zig build wazigctl` on the GitHub runner or pass --bin.", 3)
    return run_and_pass_through(command, args.dry_run, {"mutating": mutating})


def build_parser():
    parser = argparse.ArgumentParser(
        prog="vw.py",
        description="Control CLI for Wazig verification. Every command prints JSON and passes exit codes through.",
        epilog="Dispatch and read results from any machine with gh. Drive and ctl run only on a GitHub Windows runner.",
    )
    sub = parser.add_subparsers(dest="command", required=True, metavar="command")

    p = sub.add_parser("journeys", help="List every registered journey and whether it has a planted bug.")
    p.set_defaults(func=cmd_journeys)

    p = sub.add_parser("describe", help="Show one journey's registry record and planted files.")
    p.add_argument("feature")
    p.set_defaults(func=cmd_describe)

    p = sub.add_parser("run", help="Dispatch verify.yml for one journey on GitHub.")
    p.add_argument("feature")
    p.add_argument("--ref", help="Branch to run on. Default is the default branch.")
    p.add_argument("--repeat", type=int, default=1, help="Run the journey 1 to 3 times.")
    p.add_argument("--dry-run", action="store_true", help="Print the gh command and run nothing.")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("runs", help="List recent verify.yml runs.")
    p.add_argument("--feature", help="Only runs whose title names this journey.")
    p.add_argument("--limit", type=int, default=10)
    p.set_defaults(func=cmd_runs)

    p = sub.add_parser("status", help="Show the jobs and counts of one run.")
    p.add_argument("run_id", type=int)
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("evidence", help="Download a run's evidence for one journey.")
    p.add_argument("run_id", type=int)
    p.add_argument("feature")
    p.add_argument("--dir", help="Where to put it. Default is evidence/<run id>.")
    p.add_argument("--dry-run", action="store_true", help="Print the gh command and download nothing.")
    p.set_defaults(func=cmd_evidence)

    p = sub.add_parser("drive", help="On a runner: launch the app, run doctor and drive one journey.")
    p.add_argument("feature")
    p.add_argument("--bin", default="zig-out/bin")
    p.add_argument("--evidence", default="verification-evidence")
    p.add_argument("--expected-version", default="")
    p.add_argument("--dry-run", action="store_true", help="Print the command and run nothing.")
    p.set_defaults(func=cmd_drive)

    p = sub.add_parser("ctl", help="On a runner: pass a command to wazigctl. Reads are free, writes need --allow-write.")
    p.add_argument("--bin", default="zig-out/bin")
    p.add_argument("--dry-run", action="store_true", help="Print the command and run nothing.")
    p.add_argument("--allow-write", action="store_true", help="Allow a command that changes app state.")
    p.add_argument("ctl_args", nargs=argparse.REMAINDER)
    p.set_defaults(func=cmd_ctl)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "ctl_args", None) and args.ctl_args[0] == "--":
        args.ctl_args = args.ctl_args[1:]
    try:
        return args.func(args)
    except CliError as error:
        json.dump({"error": error.message, "next": error.next_step}, sys.stderr)
        sys.stderr.write("\n")
        return error.code


if __name__ == "__main__":
    sys.exit(main())
