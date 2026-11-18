import json
import sys


def count_checks(checks):
    return {
        'entries': len(checks),
        'not_skipped': sum(check['state'] != 'SKIPPED' for check in checks),
    }


if __name__ == '__main__':
    print(json.dumps(count_checks(json.load(sys.stdin)), sort_keys=True))
