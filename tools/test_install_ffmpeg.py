import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tools/verify-wazig/install-ffmpeg.ps1"
CALL = "tools/verify-wazig/install-ffmpeg.ps1"


class InstallFfmpegTests(unittest.TestCase):
    def test_script_retries_and_checks_the_tool_exists(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("Get-Command ffmpeg", text)
        self.assertIn("for ($i = 1; $i -le $attempts; $i++)", text)
        self.assertRegex(text, r"\$attempts = [2-9]")
        self.assertTrue(text.rstrip().splitlines()[-1].startswith("throw "))

    def test_exit_code_alone_never_counts_as_installed(self):
        text = SCRIPT.read_text(encoding="utf-8")
        condition = re.search(r"if \((.*)\) \{\n\s+ffmpeg -version", text).group(1)
        self.assertIn("Get-Command ffmpeg", condition)
        self.assertIn("$LASTEXITCODE -eq 0", condition)

    def test_workflows_use_the_script_and_never_a_bare_choco_install(self):
        for workflow in sorted((ROOT / ".github/workflows").glob("*.yml")):
            text = workflow.read_text(encoding="utf-8")
            self.assertNotIn("choco install ffmpeg", text, workflow.name)
        users = [
            workflow.name
            for workflow in sorted((ROOT / ".github/workflows").glob("*.yml"))
            if CALL in workflow.read_text(encoding="utf-8")
        ]
        self.assertEqual(users, ["ci.yml", "planted.yml", "verify.yml"])
        self.assertEqual((ROOT / ".github/workflows/verify.yml").read_text(encoding="utf-8").count(CALL), 1)
        self.assertEqual((ROOT / ".github/workflows/planted.yml").read_text(encoding="utf-8").count(CALL), 1)


if __name__ == "__main__":
    unittest.main()
