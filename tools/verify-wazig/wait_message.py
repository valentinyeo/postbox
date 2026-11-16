import json
import sys


def build_message(step, expected, observed, elapsed):
    return f"Timed out: {step}; expected: {expected}; observed: {observed}; elapsed: {elapsed:.2f} seconds"


if __name__ == '__main__':
    print(build_message(**json.load(sys.stdin)))
