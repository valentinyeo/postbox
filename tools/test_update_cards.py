import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import update_cards


ROOT = Path(__file__).resolve().parent.parent


class UpdateCardTest(unittest.TestCase):
    def test_plain_product_line(self):
        self.assertEqual(update_cards.card_text("Summary\n\nCard: Alt+1 stays WhatsApp after you empty it\n"), "Alt+1 stays WhatsApp after you empty it")
        update_cards.validate("Card: The update card lists what changed in each update", ["src/main.zig"])

    def test_missing_card_rejected_for_app_and_assets(self):
        for files in (["src/main.zig"], ["assets/icon.svg"]):
            with self.subTest(files=files), self.assertRaises(ValueError):
                update_cards.validate("Tests passed", files)

    def test_real_past_pr_shape_is_not_a_product_card(self):
        title = "IGSH-715: inboxes keep their Alt+number; window title shows the inbox name"
        body = "Inbox slots stay fixed when an inbox is empty, and the window title leads with the current inbox.\n\nThe first commit only extends the views verify journey, so it fails on current main; the fix follows."
        with self.assertRaises(ValueError):
            update_cards.validate(body, ["src/main.zig"])
        with self.assertRaises(ValueError):
            update_cards.card_text("Card: " + title)

    def test_reject_developer_text(self):
        for text in ("Fix IGSH-123", "Fix #123", "Change main.zig", "Change installer.wxs", "See https://example.com", "See www.example.com", "See https://example", "x" * 81, "", "none\nCard: Another change"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                update_cards.validate("Card: " + text, ["src/main.zig"])

    def test_eighty_characters_and_unicode(self):
        self.assertEqual(update_cards.card_text("Card: " + "é" * 80), "é" * 80)

    def test_none_only_for_non_product_changes(self):
        update_cards.validate("Card: none", ["tools/check.py"])
        update_cards.validate("Card: none", ["src/update_test.zig"])
        update_cards.validate("Documentation", ["README.md"])
        for files in (["src/main.zig"], ["assets/icon.svg"], ["src/update_test.zig", "src/main.zig"]):
            with self.subTest(files=files), self.assertRaises(ValueError):
                update_cards.validate("Card: none", files)

    def test_release_newest_first_deduplicates_pulls_and_skips_none(self):
        old = {"number": 1, "merged_at": "2026-01-01", "body": "Card: Older change"}
        new = {"number": 2, "merged_at": "2026-01-03", "body": "Card: Newest change"}
        hidden = {"number": 3, "merged_at": "2026-01-04", "body": "Card: none"}
        invalid = {"number": 4, "merged_at": "2026-01-05", "body": "Card: Fix IGSH-123"}
        self.assertEqual(update_cards.release_body([old, new, old, hidden, invalid]), "- Newest change\n- Older change\n")

    def test_release_fallback(self):
        for pulls in ([], [{"number": 1, "merged_at": "2026-01-01", "body": None}]):
            self.assertEqual(update_cards.release_body(pulls), "- Small fixes and speed improvements\n")

    @patch("update_cards.command")
    def test_paginated_api(self, command):
        command.return_value = '[{"number":1}]\n[{"number":2}]'
        self.assertEqual(list(update_cards.api_pages("repos/example/app/pulls")), [{"number": 1}, {"number": 2}])
        command.assert_called_once_with("gh", "api", "--paginate", "repos/example/app/pulls")

    @patch("update_cards.api_pages")
    @patch("update_cards.command")
    def test_release_range_previous_tag_and_merged_commits_only(self, command, api):
        command.side_effect = ["v1.0.0\nv1.0.1\nv1.0.2", "new\nold"]
        api.return_value = [
            {"number": 1, "merged_at": "2026-01-01", "merge_commit_sha": "old", "body": "Card: Older change"},
            {"number": 2, "merged_at": "2026-01-02", "merge_commit_sha": "new", "body": "Card: Newest change"},
            {"number": 3, "merged_at": "2026-01-03", "merge_commit_sha": "outside", "body": "Card: Wrong range"},
            {"number": 4, "merged_at": None, "merge_commit_sha": "new", "body": "Card: Not merged"},
        ]
        self.assertEqual(update_cards.compose_release("example/app", "v1.0.2"), "- Newest change\n- Older change\n")
        self.assertEqual(command.call_args_list[1].args, ("git", "rev-list", "v1.0.1..v1.0.2"))

    @patch("update_cards.api_pages", return_value=[])
    @patch("update_cards.command", side_effect=["v1.0.0", "first"])
    def test_first_release(self, command, api):
        self.assertEqual(update_cards.compose_release("example/app", "v1.0.0"), "- Small fixes and speed improvements\n")
        self.assertEqual(command.call_args_list[1].args, ("git", "rev-list", "v1.0.0"))

    def test_cli_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            body = Path(directory) / "body.txt"
            files = Path(directory) / "files.txt"
            body.write_text("No product line")
            files.write_text("src/main.zig\n")
            args = ["python3", str(ROOT / "tools/update_cards.py"), "check", "--body-file", str(body), "--files", str(files)]
            failed = subprocess.run(args, capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("Card:", failed.stderr)
            body.write_text("Card: Updates show what changed")
            passed = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(passed.returncode, 0, passed.stderr)
            self.assertIn("Update card line verified", passed.stdout)

    def test_workflow_and_ship_wiring(self):
        workflow = (ROOT / ".github/workflows/pr-title.yml").read_text()
        self.assertIn("types: [opened, edited, synchronize]", workflow)
        self.assertIn("tools/update_cards.py check", workflow)
        self.assertIn("--paginate", workflow)
        self.assertIn("previous_filename", workflow)
        release = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertIn("tools/update_cards.py release-notes", release)
        self.assertNotIn("--generate-notes", release)
        self.assertIn('--notes-file "$RUNNER_TEMP/release-notes.txt"', release)
        self.assertIn("gh release edit", release)
        ship = (ROOT / "tools/ship.sh").read_text()
        self.assertIn('CARD_TEXT="$3"', ship)
        self.assertIn('Card: \'"$3"', ship)
        self.assertLess(ship.index("from update_cards import validate"), ship.index("git push"))


if __name__ == "__main__":
    unittest.main()
