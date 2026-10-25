import argparse
import os
from pathlib import Path
import subprocess
from check_hub_only import negative_controls, verify

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.parse_args()
    negative_controls()
    verify()
    subprocess.run([os.environ['ZIG'], 'test', 'src/hub_test.zig', '--test-filter', 'telegram'], cwd=ROOT, check=True)
    print('Telegram direct login retired; hub protocol and retirement controls passed')


if __name__ == '__main__':
    main()
