import argparse
import json
from pathlib import Path
import re


def check_results(data, inputs, version, detect):
    assert data['version'] == version, 'Wrong executable version'
    assert data['host'] == 'api.anthropic.com', 'Not the configured product provider'
    assert data['model'] == 'claude-haiku-5-5', 'Not the product formatter model'
    expected = {row['id']: row for row in inputs}
    assert len(expected) == 10
    assert len(data['cases']) == 10
    assert {row['id'] for row in data['cases']} == set(expected)
    assert sum(row['language'] == 'de' for row in inputs) == 5
    assert sum(row['language'] == 'en' for row in inputs) == 5
    for row in data['cases']:
        source = expected[row['id']]
        assert row['language'] == source['language']
        assert row['transcript'] == source['transcript'], 'Saved input changed'
        sections = re.split(r'\n\s*---+\s*\n', row['formatted'], maxsplit=1)
        assert len(sections) == 2, f"Missing summary boundary: {row['id']}"
        summary, body = sections
        assert re.match(r'^1[.)] ', summary), 'Missing summary'
        headings = re.findall(r'^\d+[.)]?\s+(.+)$', body, re.M)
        assert headings, 'No generated headings'
        summary_lines = [line.strip() for line in summary.splitlines() if line.strip()]
        for field in [*summary_lines, *headings]:
            assert detect(field) == source['language'], f"Mixed generated field in {row['id']}: {field}"
        lines = [line.strip() for line in body.splitlines() if line.strip()]
        if row['id'].endswith('cutoff'):
            assert not lines[-1].startswith(('-', '•')), 'Missing cutoff note'
            assert detect(lines[-1]) == source['language'], 'Wrong cutoff language'
        if row['id'] == 'de-mixed':
            bullets = '\n'.join(line for line in lines if line.startswith(('-', '•')))
            assert 'Real Life' in bullets and 'Energy' in bullets, 'Spoken English phrases were translated'
    return 'VOICE_LANGUAGE_VERIFIED: five German, five English; summary, each header and cutoff; spoken phrases preserved'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('results', type=Path)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    from lingua import Language, LanguageDetectorBuilder
    detector = LanguageDetectorBuilder.from_languages(Language.GERMAN, Language.ENGLISH).build()
    def detect(text):
        found = detector.detect_language_of(text)
        return {Language.GERMAN: 'de', Language.ENGLISH: 'en'}.get(found)
    inputs = json.loads(Path(__file__).with_name('voice-language.json').read_text(encoding='utf-8'))
    print(check_results(json.loads(args.results.read_text(encoding='utf-8')), inputs, args.version, detect))


if __name__ == '__main__':
    main()
