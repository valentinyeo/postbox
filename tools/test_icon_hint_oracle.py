import copy
from pathlib import Path
import runpy
import unittest


check_transition = runpy.run_path(str(Path(__file__).parent / 'verify-wazig/check-icon-hints-evidence.py'))['check_transition']


def observation(visible, begin, end, current, tools):
    tip = {'hwnd': 9, 'visible': visible, 'current': current, 'tools': tools, 'autopop_ms': 5000}
    return {'visible': visible, 'hwnd': 9 if visible else 0, 'text': 'Reply' if visible else '',
            'begin_ticks': begin, 'end_ticks': end, 'ticks': end, 'frequency': 1000,
            'tooltips': [tip], 'first_tools': [copy.deepcopy(tip)]}


def fresh():
    tool = {'owner': 1, 'id': 3000, 'flags': 16, 'rect': [1, 2, 3, 4]}
    reset = observation(False, 900, 990, tool, [tool])
    first = observation(True, 1400, 1500, tool, [tool])
    before = observation(True, 1510, 1520, tool, [tool])
    after = observation(False, 1620, 1630, tool, [tool])
    generation = {'sequence': 1, 'pid': 7, 'start_ticks': '3', 'exe': 'fixture', 'sha256': 'hash', 'commit': 'revision',
                  'frequency': 1000, 'tooltip_hwnd': 9, 'autopop_ms': 5000, 'text': 'Reply', 'tool': tool,
                  'target_hwnd': 1, 'target_screen_rect': [10, 10, 20, 20], 'reset': reset,
                  'reset_cursor': {'x': 5, 'y': 5, 'owner_hwnd': 2, 'owner_pid': 7},
                  'target_move': {'x': 15, 'y': 15, 'owner_hwnd': 1, 'owner_pid': 7, 'input_begin_ticks': 1000, 'input_end_ticks': 1010},
                  'first_visible': first}
    return {'generation': generation, 'before': before, 'after': after, 'pid': 7, 'start_ticks': '3',
            'exe': 'fixture', 'sha256': 'hash', 'commit': 'revision', 'transition_ticks': 1530,
            'action_begin_ticks': 1530, 'action_end_ticks': 1540}


class IconTransitionOracleTests(unittest.TestCase):
    def setUp(self):
        self.item = fresh()

    def test_prompt_disappearance_is_accepted(self):
        check_transition(self.item)

    def test_late_autopop_is_rejected(self):
        self.item['after']['begin_ticks'] = 5990
        self.item['after']['end_ticks'] = self.item['after']['ticks'] = 6000
        with self.assertRaises(AssertionError):
            check_transition(self.item)

    def test_same_visible_tool_is_rejected(self):
        self.item['after'] = observation(True, 1620, 1630, self.item['generation']['tool'], [self.item['generation']['tool']])
        with self.assertRaises(AssertionError):
            check_transition(self.item)

    def test_aged_popup_with_short_baseline_is_rejected(self):
        self.item['before']['begin_ticks'] = 5890
        self.item['before']['end_ticks'] = self.item['before']['ticks'] = 5900
        self.item['transition_ticks'] = self.item['action_begin_ticks'] = 5900
        self.item['action_end_ticks'] = 5910
        self.item['after']['begin_ticks'] = 5990
        self.item['after']['end_ticks'] = self.item['after']['ticks'] = 6000
        self.assertLess(self.item['after']['end_ticks'] - self.item['transition_ticks'], 1500)
        with self.assertRaises(AssertionError):
            check_transition(self.item)

    def test_hidden_same_header_tool_is_accepted(self):
        self.item['generation']['text'] = 'Current chat'
        self.item['generation']['first_visible']['text'] = 'Current chat'
        self.item['before']['text'] = 'Current chat'
        check_transition(self.item)

    def test_adjacent_different_tool_is_accepted(self):
        new = {'owner': 1, 'id': 3001, 'flags': 16, 'rect': [3, 2, 5, 4]}
        self.item['after'] = observation(True, 1620, 1630, new, [new])
        self.item['after']['text'] = 'React'
        check_transition(self.item)

    def test_strict_deadline_and_generation_boundaries(self):
        for transition, end in ((1530, 3030), (2001, 3500)):
            item = copy.deepcopy(self.item)
            item['after']['begin_ticks'] = end - 1
            item['after']['end_ticks'] = item['after']['ticks'] = end
            item['transition_ticks'] = item['action_begin_ticks'] = transition
            item['action_end_ticks'] = transition + 10
            if transition == 2001:
                item['before']['begin_ticks'] = 1980
                item['before']['end_ticks'] = item['before']['ticks'] = 1990
            with self.assertRaises(AssertionError):
                check_transition(item)

    def test_aged_preparation_requires_new_generation(self):
        stale = copy.deepcopy(self.item)
        stale['before']['begin_ticks'] = 5580
        stale['before']['end_ticks'] = stale['before']['ticks'] = 5590
        stale['transition_ticks'] = stale['action_begin_ticks'] = 5600
        stale['action_end_ticks'] = 5610
        stale['after']['begin_ticks'] = 5690
        stale['after']['end_ticks'] = stale['after']['ticks'] = 5700
        with self.assertRaises(AssertionError):
            check_transition(stale)
        rearmed = fresh()
        rearmed['generation']['sequence'] = 2
        check_transition(rearmed)

    def test_reset_identity_frequency_and_order_fail_closed(self):
        mutations = (
            lambda item: item['generation'].pop('reset'),
            lambda item: item['generation']['reset'].update(visible=True),
            lambda item: item['generation']['reset_cursor'].update(x=15, y=15),
            lambda item: item['generation']['target_move'].update(owner_hwnd=99),
            lambda item: item['generation'].update(tooltip_hwnd=99),
            lambda item: item['after'].update(frequency=999),
            lambda item: item['generation']['target_move'].update(input_begin_ticks=1011),
            lambda item: item['after']['tooltips'][0].update(autopop_ms=4999),
            lambda item: item['generation'].update(tool={'owner': 1, 'id': 99, 'flags': 16, 'rect': [1, 2, 3, 4]}),
            lambda item: item['generation'].update(pid=8),
        )
        for mutate in mutations:
            item = copy.deepcopy(self.item)
            mutate(item)
            with self.subTest(mutation=mutate), self.assertRaises((AssertionError, KeyError)):
                check_transition(item)


if __name__ == '__main__':
    unittest.main()
