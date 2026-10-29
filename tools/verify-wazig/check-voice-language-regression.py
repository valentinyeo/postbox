from pathlib import Path
import subprocess
import tempfile
import argparse

ROOT = Path(__file__).resolve().parents[2]
BASE = '6db8ef9'
MARKER = 'test "all generated voice fields share one dominant language'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    current = (ROOT / 'src/format_request.zig').read_text()
    tests = current[current.index(MARKER):]
    old = subprocess.check_output(['git', 'show', f'{BASE}:src/format_request.zig'], cwd=ROOT, text=True)
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'format_request.zig'
        for label, source in [('current', current), ('historical', old + '\n' + tests)]:
            path.write_text(source)
            result = subprocess.run([args.zig, 'test', str(path), '--test-filter', 'all generated voice fields'], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            print(f'{label}:\n{result.stdout}', flush=True)
            if label == 'current':
                assert result.returncode == 0 and 'All 1 tests passed' in result.stdout
            else:
                assert result.returncode != 0 and 'FAIL (TestUnexpectedResult)' in result.stdout
    print('VOICE_LANGUAGE_RED_CONTROL_VERIFIED')


if __name__ == '__main__':
    main()
