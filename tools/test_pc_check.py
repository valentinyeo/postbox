import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

TOOLS = Path(__file__).resolve().parent
SCRIPT = TOOLS / "pc_check.py"
sys.path.insert(0, str(TOOLS))
import pc_check

FAKE_LH = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAKE_LH_LOG"
if [ "$1" = status ]; then exit "${FAKE_STATUS_EXIT:-0}"; fi
if [ "$1" = shell ]; then cat "$FAKE_PROBE_FILE"; exit "${FAKE_SHELL_EXIT:-0}"; fi
exit 0
"""

FAKE_WAKE = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAKE_WAKE_LOG"
exit 0
"""

FAKE_CONTROL = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAKE_LOG"
exit 0
"""

BLACK = {"lock": False, "capture": "ok", "width": 2560, "height": 1440, "mean": 0.0, "max": 0}
LOCKED = {"lock": True, "capture": "ok", "width": 2560, "height": 1440, "mean": 61.2, "max": 233}
OPEN = {"lock": False, "capture": "ok", "width": 2560, "height": 1440, "mean": 108.4, "max": 240}
UNPHOTOGRAPHED = {"lock": False, "capture": "error", "error": "The handle is invalid", "mean": -1, "max": -1}


class PcCheckTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.lh_log = self.root / "lh.log"
        self.wake_log = self.root / "wake.log"
        self.control_log = self.root / "systemctl.log"
        self.probe_file = self.root / "probe.json"
        for name, body in (("lh", FAKE_LH), ("mp-sessions", FAKE_WAKE), ("systemctl", FAKE_CONTROL)):
            path = self.bin / name
            path.write_text(body, encoding="utf-8")
            path.chmod(0o755)
        self.env = {
            "PATH": str(self.bin) + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": str(self.root),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "PC_CHECK_LH": str(self.bin / "lh"),
            "PC_CHECK_WAKE": str(self.bin / "mp-sessions"),
            "PC_CHECK_SYSTEMCTL": str(self.bin / "systemctl"),
            "PC_CHECK_STATE": str(self.root / "state"),
            "FAKE_LH_LOG": str(self.lh_log),
            "FAKE_WAKE_LOG": str(self.wake_log),
            "FAKE_LOG": str(self.control_log),
            "FAKE_PROBE_FILE": str(self.probe_file),
        }

    def run_check(self, *args, reading=None, status_exit=0, shell_exit=0, at=None):
        self.probe_file.write_text(json.dumps(reading if reading is not None else OPEN), encoding="utf-8")
        env = dict(self.env)
        env["FAKE_STATUS_EXIT"] = str(status_exit)
        env["FAKE_SHELL_EXIT"] = str(shell_exit)
        if at:
            env["PC_CHECK_NOW"] = at
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            capture_output=True,
            text=True,
            timeout=120,
            env=env,
            cwd=str(self.root),
        )

    def lines(self):
        log = self.root / "state" / "pc-check.log"
        return log.read_text(encoding="utf-8").splitlines() if log.exists() else []

    def wakes(self):
        return self.wake_log.read_text(encoding="utf-8").splitlines() if self.wake_log.exists() else []

    def test_a_black_screen_is_logged_as_black(self):
        done = self.run_check(reading=BLACK)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(len(self.lines()), 1)
        self.assertIn("state=black", self.lines()[0])
        self.assertIn("detail=max-luma-0", self.lines()[0])
        self.assertEqual(self.wakes(), [])

    def test_an_unreachable_pc_is_logged_as_offline(self):
        done = self.run_check(reading=OPEN, status_exit=1)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("state=offline", self.lines()[0])
        self.assertIn("detail=no-agent", self.lines()[0])
        self.assertEqual(self.wakes(), [])

    def test_a_missing_helper_is_named_instead_of_silently_offline(self):
        self.env["PC_CHECK_LH"] = str(self.root / "missing-lh")
        done = self.run_check(reading=OPEN)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("state=offline", self.lines()[0])
        self.assertIn("detail=no-helper", self.lines()[0])

    def test_a_pc_that_cannot_be_photographed_is_not_called_open(self):
        done = self.run_check(reading=OPEN, shell_exit=1)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("state=offline", self.lines()[0])
        self.assertIn("detail=no-answer", self.lines()[0])
        self.assertEqual(self.wakes(), [])

    def test_the_lock_screen_and_an_unphotographable_desktop_are_locked(self):
        self.run_check(reading=LOCKED)
        self.run_check(reading=UNPHOTOGRAPHED)
        self.assertEqual([line.split(" ")[1] for line in self.lines()], ["state=locked", "state=locked"])
        self.assertIn("detail=logon-screen", self.lines()[0])
        self.assertIn("detail=no-picture", self.lines()[1])
        self.assertEqual(self.wakes(), [])

    def test_the_open_desktop_is_logged_and_wakes_the_chat(self):
        done = self.run_check(reading=OPEN)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("state=open", self.lines()[0])
        self.assertIn("wake=sent", self.lines()[0])
        self.assertEqual(len(self.wakes()), 1)
        self.assertTrue(self.wakes()[0].startswith("send Postbox "), self.wakes()[0])
        self.assertIn("PC is open", self.wakes()[0])

    def test_one_status_line_per_hour_and_append_only(self):
        self.run_check(reading=BLACK, at="2026-11-23T10:00:00Z")
        self.run_check(reading=OPEN, at="2026-11-23T11:00:00Z")
        self.run_check(reading=BLACK, at="2026-11-23T12:00:00Z")
        self.assertEqual(len(self.lines()), 3)
        self.assertTrue(self.lines()[0].startswith("2026-11-23T10:00:00Z state=black"))
        self.assertTrue(self.lines()[2].startswith("2026-11-23T12:00:00Z state=black"))

    def test_the_wake_waits_an_hour_and_needs_the_pc_open(self):
        self.run_check(reading=OPEN, at="2026-11-23T10:00:00Z")
        self.run_check(reading=OPEN, at="2026-11-23T10:30:00Z")
        self.assertEqual(len(self.wakes()), 1)
        self.run_check(reading=BLACK, at="2026-11-23T11:10:00Z")
        self.run_check(reading=OPEN, at="2026-11-23T11:20:00Z")
        self.assertEqual(len(self.wakes()), 2)
        self.assertEqual([line.split(" ")[1] for line in self.lines()], ["state=open", "state=open", "state=black", "state=open"])

    def test_the_picture_is_never_written_to_disk(self):
        self.run_check(reading=OPEN)
        payloads = self.lh_log.read_text(encoding="utf-8")
        self.assertIn("CopyFromScreen", payloads)
        self.assertIn("LogonUI", payloads)
        self.assertIn("ConvertTo-Json", payloads)
        for forbidden in ("Save(", ".png", ".bmp", ".jpg", "get_Item", "tempfile"):
            self.assertNotIn(forbidden, payloads)
        images = [path for path in self.root.rglob("*") if path.suffix.lower() in {".png", ".bmp", ".jpg", ".jpeg", ".gif"}]
        self.assertEqual(images, [])

    def test_the_sampler_covers_one_hour_of_watching(self):
        total = pc_check.samples(SimpleNamespace(samples=0, watch=60, every=120))
        self.assertEqual(total, 30)
        self.assertEqual(pc_check.samples(SimpleNamespace(samples=0, watch=60, every=900)), 4)
        self.assertEqual(pc_check.samples(SimpleNamespace(samples=0, watch=0, every=120)), 1)

    def test_the_sampler_writes_one_line_per_sample_and_wakes_once(self):
        done = self.run_check("--samples", "3", "--every", "0", reading=OPEN)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(len(self.lines()), 3)
        self.assertEqual([line.split(" ")[1] for line in self.lines()], ["state=open"] * 3)
        self.assertEqual(len(self.wakes()), 1)

    def test_the_hourly_timer_installs_and_switches_off(self):
        units = self.root / "units"
        done = self.run_check("--install-timer", str(units))
        self.assertEqual(done.returncode, 0, done.stderr)
        timer = (units / "pc-check.timer").read_text(encoding="utf-8")
        service = (units / "pc-check.service").read_text(encoding="utf-8")
        self.assertIn("OnCalendar=hourly", timer)
        self.assertIn("Persistent=true", timer)
        self.assertIn("WantedBy=timers.target", timer)
        self.assertIn(" --once", service)
        self.assertIn(str(SCRIPT), service)
        controls = self.control_log.read_text(encoding="utf-8").splitlines()
        self.assertIn("--user enable --now pc-check.timer", controls)
        done = self.run_check("--uninstall-timer", str(units))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertFalse((units / "pc-check.timer").exists())
        self.assertFalse((units / "pc-check.service").exists())
        self.assertIn("--user disable --now pc-check.timer", self.control_log.read_text(encoding="utf-8"))

    def test_no_wake_leaves_the_chat_alone(self):
        self.run_check("--no-wake", reading=OPEN)
        self.assertIn("state=open", self.lines()[0])
        self.assertIn("wake=no", self.lines()[0])
        self.assertEqual(self.wakes(), [])


if __name__ == "__main__":
    unittest.main()
