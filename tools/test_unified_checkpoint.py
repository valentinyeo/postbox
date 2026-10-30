import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--zig', required=True)
args = parser.parse_args()
source = (root / 'src/main.zig').read_text()
parts = []
for name in ('wacliJobArgs', 'beginUnifiedSend', 'retryUnifiedSend', 'sendRetryDelayMs', 'retryUnifiedRefill', 'commitUnifiedOutcome', 'finishUnifiedSend', 'tickUnifiedOutbox'):
    start = source.index(f'fn {name}(')
    end = source.index('\n}\n', start) + 3
    parts.append(source[start:end])
parts.insert(0, re.search(r'^const WacliJobKind = enum\(u8\) \{[^\n]+\};', source, re.M).group())
parts.insert(0, re.search(r'^const WacliJob = struct \{.*?^};', source, re.M | re.S).group())
parts.insert(0, re.search(r'^const WacliResult = struct \{.*?^};', source, re.M | re.S).group())
for name in ('max_wacli_args', 'wacli_arg_cap', 'max_pending_sends'):
    parts.insert(0, re.search(rf'^const {name} = .*?;', source, re.M).group())
with tempfile.TemporaryDirectory(prefix='unified-checkpoint-') as directory:
    target = Path(directory)
    for name in ('outbox.zig', 'unified_snapshot.zig', 'transport.zig', 'chat_key.zig'):
        (target / name).write_text((root / 'src' / name).read_text())
    fixture = (root / 'tools/unified_checkpoint_test.zig').read_text()
    (target / 'test.zig').write_text(fixture + '\n' + '\n'.join(parts))
    subprocess.run([args.zig, 'test', str(target / 'test.zig')], check=True)
