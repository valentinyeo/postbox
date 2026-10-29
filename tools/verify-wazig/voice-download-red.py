from pathlib import Path
import subprocess

path = Path('src/main.zig')
current = path.read_text(encoding='utf-8')
historical = subprocess.check_output(['git', 'show', '77ec20f:src/main.zig'], text=True, encoding='utf-8')

def function(source):
    start = source.index('fn downloadMedia(')
    end = source.index('\n}\n', start) + 3
    return source[start:end]

old = function(historical)
assert 'a.pending_send_count > 0' in old
assert '!hubConfigured(a)' not in old
path.write_text(current.replace(function(current), old, 1), encoding='utf-8', newline='\n')
print('Historical downloadMedia from 77ec20f restored')
