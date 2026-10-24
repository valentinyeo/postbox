import argparse
import hashlib
import json
from pathlib import Path
import urllib.request


REVISION = '13ee711e222ea17fe537bfea953c687866f16411'
URL = f'https://raw.githubusercontent.com/iamcal/emoji-data/{REVISION}/emoji.json'
TARGET = Path(__file__).resolve().parents[1] / 'src/slack_emoji.tsv'


def generate(raw):
    entries = {}
    for row in json.loads(raw):
        for name in row['short_names']:
            entries[name] = ''.join(chr(int(cp, 16)) for cp in row['unified'].split('-'))
            for tones, variation in row.get('skin_variations', {}).items():
                suffix = ''.join('::skin-tone-' + str(int(cp, 16) - 0x1F3FB + 2) for cp in tones.split('-'))
                entries[name + suffix] = ''.join(chr(int(cp, 16)) for cp in variation['unified'].split('-'))
    return ''.join(name + '\t' + value + '\n' for name, value in sorted(entries.items()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    raw = args.source.read_bytes() if args.source else urllib.request.urlopen(URL).read()
    rendered = generate(raw)
    if args.check:
        assert TARGET.read_text(encoding='utf-8') == rendered
    else:
        TARGET.write_text(rendered, encoding='utf-8', newline='\n')
    print(f'Emoji table: {len(rendered.splitlines())} names; upstream SHA256 {hashlib.sha256(raw).hexdigest()}')


if __name__ == '__main__':
    main()
