import os
import unittest
from unittest import mock

import check_private_markers
from check_private_markers import load_markers, private_paths, scan_text

PLANTED = "Install every new release on his PC (ZZDEVICE) right away."


class PrivateMarkers(unittest.TestCase):
    def test_planted_marker_is_found(self):
        markers = load_markers("\\bZZDEVICE\\b\n")
        self.assertEqual(scan_text("CLAUDE.md", "ok\n" + PLANTED, markers), [("CLAUDE.md", 2, 1)])

    def test_word_boundary_and_case(self):
        markers = load_markers("\\bZZDEVICE\\b")
        self.assertEqual(scan_text("a", "zzdevice ZZDEVICES xZZDEVICE", markers), [])

    def test_blank_lines_are_not_markers(self):
        self.assertEqual(len(load_markers("\n  \nA\n\n")), 1)

    def test_empty_secret_fails_closed(self):
        with mock.patch.dict(os.environ, {"PRIVATE_MARKERS": ""}):
            self.assertEqual(check_private_markers.main([]), 2)

    def test_pr_body_is_scanned(self):
        env = {"PRIVATE_MARKERS": "ZZDEVICE", "PR_TITLE": "fine", "PR_BODY": "tested on ZZDEVICE"}
        with mock.patch.dict(os.environ, env), mock.patch.object(check_private_markers, "git", return_value=b""):
            self.assertEqual(check_private_markers.scan_pr(load_markers("ZZDEVICE"), "a", "b"), [("PR body", 1, 1)])

    def test_private_agent_files_are_refused(self):
        paths = ["HANDOFF.md", ".claude/skills/INDEX.md", ".claude/skills", "board.yml", "src/main.zig", ".claude/hooks/preflight-guard.sh"]
        self.assertEqual(private_paths(paths), ["HANDOFF.md", ".claude/skills/INDEX.md", ".claude/skills", "board.yml"])


if __name__ == "__main__":
    unittest.main()
