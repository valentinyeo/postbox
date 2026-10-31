import copy
from pathlib import Path
import runpy
import unittest


check_transition = runpy.run_path(str(Path(__file__).parent / 'verify-wazig/check-icon-hints-evidence.py'))['check_transition']


class IconTransitionOracleTests(unittest.TestCase):
    def setUp(self):
        tool = {'owner': 1, 'id': 3000, 'flags': 16, 'rect': [1, 2, 3, 4]}
        tooltip = {'current': tool, 'tools': [tool], 'autopop_ms': 5000}
        self.item = {
            'before': {'visible': True, 'hwnd': 1, 'text': 'Reply', 'ticks': 1000, 'frequency': 1000, 'tooltips': [tooltip]},
            'after': {'visible': False, 'hwnd': 0, 'text': '', 'ticks': 1100, 'frequency': 1000, 'tooltips': [copy.deepcopy(tooltip)]},
            'elapsed_ms': 100,
        }

    def test_prompt_disappearance_is_accepted(self):
        check_transition(self.item)

    def test_late_autopop_is_rejected(self):
        self.item['after']['ticks'] = 6000
        self.item['elapsed_ms'] = 5000
        with self.assertRaises(AssertionError):
            check_transition(self.item)

    def test_same_visible_tool_is_rejected(self):
        self.item['after']['visible'] = True
        self.item['after']['text'] = 'Reply'
        with self.assertRaises(AssertionError):
            check_transition(self.item)


if __name__ == '__main__':
    unittest.main()
