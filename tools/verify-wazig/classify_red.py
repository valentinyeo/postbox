import argparse
from pathlib import Path
import sys


def classify_red(feature, evidence, exit_code, passed_message):
    if exit_code == 0:
        raise ValueError(passed_message)
    marker = evidence / 'journey-check-failed.txt'
    if not marker.is_file():
        raise ValueError('no journey check failure marker; infrastructure failure is not a repro')
    check = marker.read_text(encoding='utf-8-sig').strip()
    prefix = f'{feature}: '
    if not check.startswith(prefix) or not check[len(prefix):].strip():
        raise ValueError('invalid journey check failure marker')
    return check


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--feature', required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--exit-code', type=int, required=True)
    parser.add_argument('--passed-message', default='repro passed on base, so it does not reproduce the bug')
    args = parser.parse_args()
    try:
        print(classify_red(args.feature, args.evidence, args.exit_code, args.passed_message))
    except (ValueError, OSError) as error:
        sys.exit(str(error))
