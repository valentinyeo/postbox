import json
from pathlib import Path
import subprocess
import sys
import unittest


class WaitMessageTests(unittest.TestCase):
    def test_timeout_reports_expected_observation_and_elapsed(self):
        script = Path(__file__).parent / 'verify-wazig' / 'wait_message.py'
        data = {'step': 'mention roster', 'expected': 'roster visible',
                'observed': 'foreground=Postbox; focused=composer', 'elapsed': 20.125}
        result = subprocess.run([sys.executable, str(script)], input=json.dumps(data),
                                capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip(), 'Timed out: mention roster; expected: roster visible; observed: foreground=Postbox; focused=composer; elapsed: 20.12 seconds')


if __name__ == '__main__':
    unittest.main()
