import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

BLACK_MAX_LUMA = 16
CHAT = os.environ.get("PC_CHECK_WAKE_CHAT", "Postbox")


def locate(name):
    found = shutil.which(name)
    if found:
        return found
    for base in (Path.home() / ".local/bin", Path.home() / ".multiprompt-runtime"):
        candidate = base / name
        if candidate.is_file():
            return str(candidate)
    return name


LH = locate(os.environ.get("PC_CHECK_LH", "lh"))
WAKE = locate(os.environ.get("PC_CHECK_WAKE", "mp-sessions"))
SYSTEMCTL = locate(os.environ.get("PC_CHECK_SYSTEMCTL", "systemctl"))

PROBE = (
    "$out = [ordered]@{ lock = $false; capture = 'ok'; error = ''; width = 0; height = 0; mean = -1; max = -1 };"
    " $out.lock = [bool](Get-Process -Name LogonUI,LockApp -ErrorAction SilentlyContinue);"
    " try {"
    " Add-Type -AssemblyName System.Windows.Forms,System.Drawing;"
    " $b = [System.Windows.Forms.SystemInformation]::VirtualScreen;"
    " $bmp = New-Object System.Drawing.Bitmap $b.Width,$b.Height;"
    " $g = [System.Drawing.Graphics]::FromImage($bmp);"
    " $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size);"
    " $sum = 0; $n = 0; $max = 0;"
    " for ($y = 0; $y -lt $b.Height; $y += 16) {"
    " for ($x = 0; $x -lt $b.Width; $x += 16) {"
    " $c = $bmp.GetPixel($x, $y);"
    " $l = [int](0.2126 * $c.R + 0.7152 * $c.G + 0.0722 * $c.B);"
    " $sum += $l; $n += 1; if ($l -gt $max) { $max = $l }"
    " } };"
    " $out.width = $b.Width; $out.height = $b.Height;"
    " $out.mean = [math]::Round($sum / [math]::Max($n, 1), 1); $out.max = $max;"
    " $g.Dispose(); $bmp.Dispose()"
    " } catch { $out.capture = 'error'; $out.error = $_.Exception.Message }"
    " $out | ConvertTo-Json -Compress"
)

SERVICE = """[Unit]
Description=Postbox PC screen check

[Service]
Type=oneshot
ExecStart={exec_start}
"""

TIMER = """[Unit]
Description=Hourly Postbox PC screen check

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
"""


def now_utc():
    frozen = os.environ.get("PC_CHECK_NOW")
    if frozen:
        return datetime.fromisoformat(frozen.replace("Z", "+00:00")).astimezone(timezone.utc)
    return datetime.now(timezone.utc)


def stamp(moment):
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def state_dir():
    base = os.environ.get("PC_CHECK_STATE") or str(
        Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "pc-check"
    )
    return Path(base)


def log_path():
    return Path(os.environ.get("PC_CHECK_LOG") or (state_dir() / "pc-check.log"))


def run(args, timeout):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError):
        return None


def probe(timeout):
    if not Path(LH).is_file():
        return None, "no-helper"
    agent = run([LH, "status"], 60)
    if agent is None or agent.returncode != 0:
        return None, "no-agent"
    shell = run([LH, "shell", PROBE, "--timeout", str(timeout)], timeout + 60)
    if shell is None or shell.returncode != 0:
        return None, "no-answer"
    text = shell.stdout
    start = text.find("{")
    if start < 0:
        return None, "no-reading"
    try:
        reading = json.loads(text[start:].strip())
    except json.JSONDecodeError:
        return None, "no-reading"
    if not isinstance(reading, dict):
        return None, "no-reading"
    return reading, ""


def classify(reading, detail):
    if reading is None:
        return "offline", detail
    if reading.get("lock"):
        return "locked", "logon-screen"
    if reading.get("capture") != "ok":
        return "locked", "no-picture"
    brightest = int(float(reading.get("max", 0)))
    if brightest <= BLACK_MAX_LUMA:
        return "black", "max-luma-" + str(brightest)
    return "open", "mean-" + str(reading.get("mean")) + "-max-" + str(brightest)


def load_state(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state), encoding="utf-8")


def wake(chat, moment):
    message = "PC is open. Screen check at " + stamp(moment) + " took one picture, kept none, and wrote one log line."
    done = run([WAKE, "send", chat, message], 120)
    return done is not None and done.returncode == 0


def sample(args, state):
    reading, detail = probe(args.timeout)
    name, detail = classify(reading, detail)
    moment = now_utc()
    woke = "no"
    if name == "open" and not args.no_wake:
        previous = state.get("state")
        last = state.get("woke_at")
        due = previous != "open" or not last
        if last:
            try:
                due = due or moment - datetime.fromisoformat(last) >= timedelta(seconds=args.wake_every)
            except ValueError:
                due = True
        if due and wake(args.chat, moment):
            woke = "sent"
            state["woke_at"] = moment.isoformat()
    state["state"] = name
    line = stamp(moment) + " state=" + name + " wake=" + woke + " detail=" + detail
    path = log_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")
    print(line)
    return name


def samples(args):
    if args.samples:
        return args.samples
    if args.watch:
        return max(1, int(args.watch * 60 // max(args.every, 1)))
    return 1


def watch(args, state):
    total = samples(args)
    for index in range(total):
        sample(args, state)
        save_state(state_file(), state)
        if index + 1 < total and args.every > 0:
            time.sleep(args.every)


def state_file():
    return state_dir() / "state.json"


def unit_dir(value):
    return Path(value) if value else Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "systemd/user"


def install(where):
    where.mkdir(parents=True, exist_ok=True)
    exec_start = str(Path(sys.executable)) + " " + str(Path(__file__).resolve()) + " --once"
    (where / "pc-check.service").write_text(SERVICE.format(exec_start=exec_start), encoding="utf-8")
    (where / "pc-check.timer").write_text(TIMER, encoding="utf-8")
    run([SYSTEMCTL, "--user", "daemon-reload"], 120)
    done = run([SYSTEMCTL, "--user", "enable", "--now", "pc-check.timer"], 120)
    print("pc-check: timer installed in " + str(where) + (" and enabled" if done is not None and done.returncode == 0 else ", not enabled"))
    return done is not None and done.returncode == 0


def uninstall(where):
    run([SYSTEMCTL, "--user", "disable", "--now", "pc-check.timer"], 120)
    dropped = 0
    for name in ("pc-check.service", "pc-check.timer"):
        target = where / name
        if target.exists():
            target.unlink()
            dropped += 1
    run([SYSTEMCTL, "--user", "daemon-reload"], 120)
    print("pc-check: timer off, removed " + str(dropped) + " unit file(s)")
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description="Hourly Postbox PC screen check that keeps no picture and runs no model")
    parser.add_argument("--once", action="store_true", help="one sample, the hourly timer's mode")
    parser.add_argument("--watch", type=int, default=0, help="sample for this many minutes, the one hour watch")
    parser.add_argument("--every", type=int, default=120, help="seconds between samples in watch mode")
    parser.add_argument("--samples", type=int, default=0, help="sample exactly this many times")
    parser.add_argument("--wake-every", type=int, default=3600, help="minimum seconds between two wakes")
    parser.add_argument("--chat", default=CHAT, help="chat to wake when the PC is open")
    parser.add_argument("--no-wake", action="store_true", help="log only, never wake a chat")
    parser.add_argument("--timeout", type=int, default=60, help="seconds the PC has to answer the picture")
    parser.add_argument("--log", default=None, help="log file, defaults to the state directory")
    parser.add_argument("--install-timer", nargs="?", const="", default=None, help="write the hourly user timer")
    parser.add_argument("--uninstall-timer", nargs="?", const="", default=None, help="switch the hourly timer off")
    args = parser.parse_args(argv)
    if args.log:
        os.environ["PC_CHECK_LOG"] = args.log
    if args.once:
        args.samples = 1
    if args.install_timer is not None:
        install(unit_dir(args.install_timer))
        return 0
    if args.uninstall_timer is not None:
        uninstall(unit_dir(args.uninstall_timer))
        return 0
    state = load_state(state_file())
    watch(args, state)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
