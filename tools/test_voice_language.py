from pathlib import Path
import copy
import importlib.util
import json
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASE = '6db8ef9'
spec = importlib.util.spec_from_file_location('voice_language_evidence', ROOT / 'tools/verify-wazig/check-voice-language.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def rule(source):
    return re.search(r'pub const language_rule = "(.*)";', source)[1]


def check_contract(source, formatter):
    instruction = rule(source)
    for field in ('every summary line', 'every topic header', 'final cutoff'):
        assert field in instruction, field
    for phrase in ('decide the dominant language once', 'language of most of the words',
                   'Real Life', 'Energy', 'Preserve every spoken word exactly',
                   'never translate the transcript'):
        assert phrase in instruction, phrase
    assert '" ++ language_rule' in source
    assert 'in the SAME dominant language as the summary.' in formatter
    assert 'in the SAME dominant language as the summary and headers.' in formatter
    assert 'This is the only part you write yourself.' not in formatter


class VoiceLanguageTests(unittest.TestCase):
    def evidence(self):
        inputs = json.loads((ROOT / 'tools/verify-wazig/voice-language.json').read_text())
        rows = []
        for source in inputs:
            lang = source['language']
            text = f"1. {lang} summary\n---\n1 {lang} heading\n- {source['transcript']}"
            if source['id'].endswith('cutoff'):
                text += f"\n{lang} cutoff"
            rows.append(dict(source, formatted=text))
        return inputs, dict(version='1.2.3', host='api.anthropic.com', model='claude-haiku-5-5', cases=rows)

    def test_complete_evidence_and_real_mixed_field_controls(self):
        inputs, data = self.evidence()
        detect = lambda text: 'de' if 'de ' in text else 'en'
        validator.check_results(data, inputs, '1.2.3', detect)
        for fragment in ('de summary', 'de heading', 'de cutoff'):
            broken = copy.deepcopy(data)
            row = next(row for row in broken['cases'] if fragment in row['formatted'])
            row['formatted'] = row['formatted'].replace(fragment, 'en wrong')
            with self.subTest(fragment=fragment), self.assertRaises(AssertionError):
                validator.check_results(broken, inputs, '1.2.3', detect)
        for mutate in (lambda x: x['cases'][0].update(formatted=x['cases'][0]['formatted'].replace('de summary', 'de summary\n2. en wrong')) ,
                       lambda x: x['cases'].pop(),
                       lambda x: x.update(version='0.0.1'),
                       lambda x: x['cases'][4].update(transcript='changed input'),
                       lambda x: x['cases'][4].update(formatted=x['cases'][4]['formatted'].replace('Energy', 'Energie'))):
            broken = copy.deepcopy(data)
            mutate(broken)
            with self.assertRaises(AssertionError):
                validator.check_results(broken, inputs, '1.2.3', detect)

    def test_desktop_evidence_rejects_old_or_mismatched_output(self):
        module_spec = importlib.util.spec_from_file_location('voice_ui', ROOT / 'tools/verify-wazig/check-voice-language-ui.py')
        ui = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(ui)
        inputs, results = self.evidence()
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            def write(name, value):
                (folder / name).write_text(json.dumps(value))
            write('session.json', dict(expected_version='1.2.3', sha256='candidate', commit='head'))
            write('result.json', dict(feature='voice', status='passed'))
            write('side-effects.json', dict(production_preferences_absent=True, whatsapp_store_absent=True,
                                           telegram_store_absent=True, pending_sends=0, pending_archives=0))
            (folder / 'cleanup.txt').write_text('CLEANUP PASSED: isolated process removed')
            records = []
            for language in ('de', 'en'):
                source = next(row for row in results['cases'] if row['id'] == language + '-short')
                text = source['formatted']
                count = len(text.encode('utf-16-le')) // 2
                records.append(dict(language=language, case=source['id'], formatted=text, chars=count,
                                    screenshot=language + '.png', message='VOICE-5'))
                rows = [dict(id=f'VOICE-{n}', media_type='audio', local=True, transcript_chars=count, bubble=[0, 0, 400, 500]) for n in range(1, 6)]
                write(language + '.messages.json', dict(chat=dict(id='fixture-alpha'), messages=rows))
                (folder / (language + '.png')).write_bytes(b'\x89PNG\r\n\x1a\n' + language.encode() * 6000)
            write('displayed-results.json', records)
            self.assertEqual(ui.check_display(folder, results), 'VOICE_LANGUAGE_DESKTOP_VERIFIED')
            for mutation in ('formatted', 'version', 'screenshot'):
                changed = copy.deepcopy(records)
                altered = copy.deepcopy(results)
                if mutation == 'formatted':
                    changed[0]['formatted'] = 'old mixed language summary'
                elif mutation == 'version':
                    altered['version'] = '0.0.1'
                else:
                    changed[0]['screenshot'] = 'en.png'
                write('displayed-results.json', changed)
                with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                    ui.check_display(folder, altered)

    def test_all_generated_fields_share_one_language_contract(self):
        check_contract((ROOT / 'src/format_request.zig').read_text(),
                       (ROOT / 'src/dictation.zig').read_text())

    def test_real_previous_formatter_fails_the_contract(self):
        old = subprocess.check_output(['git', 'show', f'{BASE}:src/format_request.zig'], cwd=ROOT, text=True)
        formatter = subprocess.check_output(['git', 'show', f'{BASE}:src/dictation.zig'], cwd=ROOT, text=True)
        with self.assertRaises(AssertionError):
            check_contract(old, formatter)

    def test_previous_policy_does_not_restore_mixed_language_cache(self):
        cache = (ROOT / 'src/format_cache.zig').read_text()
        self.assertIn('const header = "wazig-voice-format v2\\n";', cache)
        self.assertIn('previous language policy cache is ignored', cache)


if __name__ == '__main__':
    unittest.main()
