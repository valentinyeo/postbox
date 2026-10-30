import argparse
from pathlib import Path
import re
import subprocess
import tempfile

def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument('--zig', required=True)
    parser.add_argument('--negative-controls', action='store_true')
    args = parser.parse_args()
    source = (root / 'src/main.zig').read_text(encoding='utf-8')
    parts = [next(line for line in source.splitlines() if line.startswith('const UnifiedFaultTransition = '))]
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
            (target / name).write_text((root / 'src' / name).read_text(encoding='utf-8'), encoding='utf-8')
        fixture = (root / 'tools/unified_checkpoint_test.zig').read_text(encoding='utf-8')
        original = '\n'.join(parts)
        controls = [(None, original)]
        if args.negative_controls:
            old = 'job.account.set(record.entry.account.slice());'
            assert original.count(old) == 1
            for name, account in [('cache-account', 'a.cache_tag.slice()'), ('display-account', 'a.view_account.slice()')]:
                controls.append((name, original.replace(old, f'job.account.set({account});', 1)))
        for name, production in controls:
            (target / 'test.zig').write_text(fixture + '\n' + production, encoding='utf-8')
            result = subprocess.run([args.zig, 'test', str(target / 'test.zig')], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if name is None:
                print(result.stdout, end='')
                if result.returncode:
                    raise SystemExit(result.returncode)
            elif result.returncode == 0 or 'FAIL (Test' not in result.stdout:
                print(result.stdout, end='')
                raise SystemExit(f'Negative control {name} did not fail a test assertion')
            else:
                print(f'NEGATIVE CONTROL {name}: ' + '; '.join(line for line in result.stdout.splitlines() if 'FAIL (Test' in line))
        writer = []
        for name in ('unifiedNativePath', 'unifiedFaultAt', 'writeOutboxAtomic', 'saveUnifiedCandidate'):
            start = source.index(f'fn {name}(')
            end = source.index('\n}\n', start) + 3
            writer.append(source[start:end])
        targeted = (root / 'tools/unified_targeted_fault_test.zig').read_text(encoding='utf-8')
        (target / 'test.zig').write_text(targeted + '\n' + '\n'.join(writer) + '\n' + original, encoding='utf-8')
        subprocess.run([args.zig, 'test', str(target / 'test.zig')], check=True)
        start = source.index('fn channelMessageVisible(')
        end = source.index('\n}\n', start) + 3
        predicate = source[start:end]
        slack = (root / 'src/slack.zig').read_text(encoding='utf-8')
        start = slack.index('pub fn isThreadReply(')
        end = slack.index('\n}\n', start) + 3
        fixture = (root / 'tools/channel_outbox_visibility_test.zig').read_text(encoding='utf-8')
        prefix = fixture + '\nconst slack = struct {\n' + slack[start:end] + '\n};\n'
        (target / 'test.zig').write_text(prefix + predicate, encoding='utf-8')
        subprocess.run([args.zig, 'test', str(target / 'test.zig')], check=True)
        if args.negative_controls:
            visibility = '(message.from_me and message.send_state != .none) or '
            assert predicate.count(visibility) == 1
            (target / 'test.zig').write_text(prefix + predicate.replace(visibility, '', 1), encoding='utf-8')
            result = subprocess.run([args.zig, 'test', str(target / 'test.zig')], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if result.returncode == 0 or 'FAIL (Test' not in result.stdout:
                print(result.stdout, end='')
                raise SystemExit('Negative control hidden local replies did not fail a test assertion')
            print('NEGATIVE CONTROL hidden local replies: ' + '; '.join(line for line in result.stdout.splitlines() if 'FAIL (Test' in line))


if __name__ == "__main__":
    main()
