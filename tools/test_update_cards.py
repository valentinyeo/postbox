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
        text = "é " * 39 + "éé"
        self.assertEqual(update_cards.card_text("Card: " + text), text)

    def test_none_only_for_non_product_changes(self):
        update_cards.validate("Card: none", ["tools/check.py"])
        update_cards.validate("Card: none", ["src/update_test.zig"])
        update_cards.validate("Documentation", ["README.md"])
        for files in (["src/main.zig"], ["assets/icon.svg"], ["src/update_test.zig", "src/main.zig"]):
            with self.subTest(files=files), self.assertRaises(ValueError):
                update_cards.validate("Card: none", files)

    def test_product_words_come_from_the_commit_subject(self):
        self.assertEqual(update_cards.card_from_subject("IGSH-1341: the message box grows with the text"), "the message box grows with the text")
        self.assertEqual(update_cards.card_from_subject("Alt+1 stays WhatsApp after you empty it"), "Alt+1 stays WhatsApp after you empty it")

    def test_test_and_ci_commits_stay_out_of_the_notes(self):
        for subject in ("IGSH-1: keep the journey check compiling", "IGSH-2: fix CI runner", "IGSH-3: add tests for drafts",
                        "IGSH-4: run the workflow again", "IGSH-5: touches main.zig", "IGSH-6: Fix #123", "IGSH-7: see https://example.com",
                        "IGSH-8: keep the menu harness compiling", "IGSH-9: fix the build order",
                        "IGSH-1346: " + "x" * 81):
            with self.subTest(subject=subject):
                self.assertIsNone(update_cards.card_from_subject(subject))

    @patch("update_cards.command")
    def test_commit_fallback_needs_a_real_app_change(self, command):
        command.side_effect = ["tools/verify-wazig/run.ps1\n.github/workflows/ci.yml\n", ]
        self.assertIsNone(update_cards.commit_product_text("sha"))
        command.side_effect = ["src/compose_layout.zig\ntools/update_cards.py\n", "IGSH-1341: the message box grows with the text\n"]
        self.assertEqual(update_cards.commit_product_text("sha"), "IGSH-1341: the message box grows with the text")
        command.side_effect = ["src/compose_layout_test.zig\n"]
        self.assertIsNone(update_cards.commit_product_text("sha"))

    @patch("update_cards.command")
    def test_commit_card_line_wins_over_a_long_subject(self, command):
        command.side_effect = ["src/main.zig\n", "IGSH-1540: a very long subject " + "x" * 80 + "\n\nUndo: revert\nCard: Archiving a chat now empties the inbox\n"]
        self.assertEqual(update_cards.commit_product_text("sha"), "IGSH-1540: Archiving a chat now empties the inbox")
        command.side_effect = ["src/main.zig\n", "IGSH-1540: subject\n\nCard: none\n"]
        self.assertIsNone(update_cards.commit_product_text("sha"))

    @patch("update_cards.command")
    def test_paginated_api(self, command):
        command.return_value = '[{"number":1}]\n[{"number":2}]'
        self.assertEqual(list(update_cards.api_pages("repos/example/app/pulls")), [{"number": 1}, {"number": 2}])
        command.assert_called_once_with("gh", "api", "--paginate", "repos/example/app/pulls")

    @patch("update_cards.commit_product_text", return_value=None)
    @patch("update_cards.api_pages")
    @patch("update_cards.command")
    def test_release_range_previous_tag_and_merged_commits_only(self, command, api, fallback):
        command.side_effect = ["v1.0.0\nv1.0.1\nv1.0.2", "new\nold"]
        api.return_value = [
            {"number": 1, "merged_at": "2026-01-01", "merge_commit_sha": "old", "title": "IGSH-1: older", "body": "Card: Older change shows up"},
            {"number": 2, "merged_at": "2026-01-02", "merge_commit_sha": "new", "title": "IGSH-2: newest", "body": "Card: Newest change shows up"},
            {"number": 3, "merged_at": "2026-01-03", "merge_commit_sha": "outside", "body": "Card: Wrong range"},
            {"number": 4, "merged_at": None, "merge_commit_sha": "new", "body": "Card: Not merged"},
        ]
        self.assertEqual(update_cards.compose_release("example/app", "v1.0.2"), "- IGSH-2: Newest change shows up\n- IGSH-1: Older change shows up\n")
        self.assertEqual(command.call_args_list[1].args, ("git", "rev-list", "v1.0.1..v1.0.2"))

    @patch("update_cards.commit_product_text", return_value=None)
    @patch("update_cards.api_pages", return_value=[])
    @patch("update_cards.command", side_effect=["v1.0.0", "first"])
    def test_first_release_has_no_filler_when_nothing_names_a_change(self, command, api, fallback):
        self.assertEqual(update_cards.compose_release("example/app", "v1.0.0"), "")
        self.assertEqual(command.call_args_list[1].args, ("git", "rev-list", "v1.0.0"))

    @patch("update_cards.commit_product_text", side_effect=["IGSH-1341: the message box grows with the text", "IGSH-1341: the message box grows with the text", None])
    @patch("update_cards.api_pages", return_value=[])
    @patch("update_cards.command")
    def test_direct_pushes_become_bullets_without_duplicates(self, command, api, fallback):
        command.side_effect = ["v1.0.0", "third\nsecond\nfirst"]
        self.assertEqual(update_cards.compose_release("example/app", "v1.0.0"), "- IGSH-1341: the message box grows with the text\n")
        self.assertEqual(command.call_args_list[1].args, ("git", "rev-list", "v1.0.0"))

    def test_igsh_1683_filler_card_lines_are_refused(self):
        for text in ("Checks and fixes", "Small fixes and speed improvements", "Bug fixes", "Improvements", "Fixes", "Tweaks"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                update_cards.validate("Card: " + text, ["src/main.zig"])

    def test_igsh_1683_every_release_line_needs_ticket_and_title(self):
        update_cards.check_notes("- IGSH-1683: Update notes name their ticket\n- IGSH-12: Chat rows keep the time inside\n")
        update_cards.check_notes("")
        for notes in ("- Checks and fixes", "- Small fixes and speed improvements", "- IGSH-1: Fixes", "- Update notes name their ticket", "- IGSH-1:"):
            with self.subTest(notes=notes), self.assertRaises(ValueError):
                update_cards.check_notes(notes)

    @patch("update_cards.commit_product_text", return_value=None)
    @patch("update_cards.api_pages")
    @patch("update_cards.command")
    def test_igsh_1683_a_change_without_a_ticket_gets_no_line(self, command, api, fallback):
        command.side_effect = ["v1.0.0", "new"]
        api.return_value = [{"number": 2, "merged_at": "2026-01-02", "merge_commit_sha": "new", "title": "no ticket here", "body": "Card: Newest change shows up"}]
        self.assertEqual(update_cards.compose_release("example/app", "v1.0.0"), "")

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
