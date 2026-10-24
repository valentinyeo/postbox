import argparse
import unittest

from test_slack_emoji import EmojiContractChecks, EmojiDataChecks, EmojiJourneyChecks


parser = argparse.ArgumentParser()
mode = parser.add_mutually_exclusive_group()
mode.add_argument('--contract', action='store_true')
mode.add_argument('--journey', action='store_true')
args = parser.parse_args()
checks, marker = (EmojiContractChecks, 'Slack emoji contract checks passed') if args.contract else (
    (EmojiJourneyChecks, 'Slack emoji journey checks passed') if args.journey else
    (EmojiDataChecks, 'Slack emoji data and integration checks passed'))
result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(checks))
if not result.wasSuccessful():
    raise SystemExit(1)
print(marker)
