import argparse
import os
from pathlib import Path
import subprocess
from check_hub_only import negative_controls, verify

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cache-dir', required=True, type=Path)
    parser.add_argument('--zig', default=os.environ.get('ZIG', 'zig'))
    args = parser.parse_args()
    negative_controls()
    verify()
    subprocess.run([args.zig, 'test', str(ROOT / 'src/hub_test.zig'), '--cache-dir', str(args.cache_dir / 'local'), '--global-cache-dir', str(args.cache_dir / 'global')], cwd=ROOT, check=True)
    print('Slack HTTP, OAuth and Socket Mode retired; hub protocol and retirement controls passed')


if __name__ == '__main__':
    main()
