import unittest

import check_revert_first as rule


def merged(number):
    return {'merged': True, 'title': 'Revert "SOFT-1: broke send"'}


def open_pr(number):
    return {'merged': False, 'title': 'Revert "SOFT-1: broke send"'}


def not_revert(number):
    return {'merged': True, 'title': 'SOFT-1: add thing'}


def missing(number):
    return None


class RevertFirstTests(unittest.TestCase):
    def test_non_fix_titles_are_ignored(self):
        self.assertIsNone(rule.check('SOFT-2: Add palette row', '', missing))

    def test_fix_without_line_fails(self):
        self.assertIn('exactly one', rule.check('Fix send queue', 'Repro: send', missing))

    def test_two_lines_fail(self):
        body = 'Revert: #5\nRevert: none, new bug'
        self.assertIn('exactly one', rule.check('Fix send queue', body, merged))

    def test_merged_revert_passes(self):
        self.assertIsNone(rule.check('SOFT-3: Fix send queue', 'Revert: #5', merged))

    def test_unmerged_revert_fails(self):
        self.assertIn('not a merged PR', rule.check('Fix send queue', 'Revert: #5', open_pr))

    def test_non_revert_pr_fails(self):
        self.assertIn('not a merged PR', rule.check('Fix send queue', 'Revert: #5', not_revert))

    def test_unknown_pr_fails(self):
        self.assertIn('not a merged PR', rule.check('Fix send queue', 'Revert: #5', missing))

    def test_reasoned_note_passes(self):
        self.assertIsNone(rule.check('Fix send queue', 'Revert: none, bug was never released', missing))

    def test_bare_none_fails(self):
        self.assertIn('write Revert', rule.check('Fix send queue', 'Revert: none', missing))

    def test_free_text_fails(self):
        self.assertIn('write Revert', rule.check('Fix send queue', 'Revert: later', missing))


if __name__ == '__main__':
    unittest.main()
