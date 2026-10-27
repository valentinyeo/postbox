import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = '2a746d7777ac7e7d1fd8ec4e5af1fd024f02e7b6'


def section(source, first, last):
    start = source.index(first)
    return source[start:source.index(last, start)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    fixed = (ROOT / 'src/main.zig').read_text()
    historical_copy = (ROOT / 'tools/fixtures/transcript-copy-2a746d7.zig').read_text()
    old = fixed.replace(section(fixed, 'fn copyMarkedTranscripts(', 'fn handleCanvasClick('), historical_copy, 1)
    fixture = (ROOT / 'src/transcript_copy_test.zig').read_text()
    with tempfile.TemporaryDirectory(prefix='transcript-copy-regression-') as directory:
        path = Path(directory) / 'transcripts.zig'
        for label, source in [('historical', old), ('fixed', fixed)]:
            text = fixture + ''.join(section(source, first, last) for first, last in [
                ('fn WideText(', 'const Chat = struct'),
                ('fn isAudio(', 'fn ensureAudioPlayer('),
                ('fn messageMarked(', 'fn handleCanvasClick('),
                ('fn saveTranscriptCache(', 'fn ensureTranscribeSession('),
            ])
            path.write_text(text)
            result = subprocess.run([
                args.zig, 'test', '--dep', 'chat_key', '--dep', 'format_cache',
                '-Mroot=' + str(path), '-Mchat_key=' + str(ROOT / 'src/chat_key.zig'),
                '-Mformat_cache=' + str(ROOT / 'src/format_cache.zig'),
                '--test-filter', 'legacy summary sidecars',
            ], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            print(label + (' ' + BASE if label == 'historical' else '') + ':\n' + result.stdout, flush=True)
            assert 'legacy summary sidecars' in result.stdout, 'legacy behavior case did not execute'
            if label == 'historical':
                assert result.returncode != 0 and 'FAIL (TestExpectedEqual)' in result.stdout, 'old summary export escaped the behavior test'
            else:
                assert result.returncode == 0 and 'All 1 tests passed' in result.stdout, 'verified raw export failed'
    print('LEGACY_RAW_PROVENANCE_VERIFIED: old summary export is red; verified raw export is green')


if __name__ == '__main__':
    main()
