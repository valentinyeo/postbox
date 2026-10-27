import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('transcript_copy_evidence', ROOT / 'tools/verify-wazig/check-transcript-copy.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class TranscriptCopyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        rows = [dict(id=f'VOICE-{index}', time=f'2026-01-01T12:0{index}:00Z', raw=f'Raw {index}: Grüße, café\nSecond line stays raw.') for index in (3, 4, 5)]
        combined = '\r\n\r\n'.join(row['raw'] for row in rows)
        missing = '\r\n\r\n'.join(row['raw'] for row in rows if row['id'] != 'VOICE-4')
        self.files = {
            'transcript-copy.json': dict(raw_rows=rows, actual=combined, expected=combined,
                                         marked=['VOICE-3', 'VOICE-TEXT', 'VOICE-4', 'VOICE-5'],
                                         labels=['Copy all transcripts'], title='4 messages marked · Copied 3 transcripts'),
            'transcript-missing.json': dict(actual=missing, expected=missing, missing_id='VOICE-4', missing_time='12:04',
                                            title='Copied 2 transcripts. Missing: 12:04'),
            'transcript-selection.json': dict(range=['VOICE-3', 'VOICE-TEXT', 'VOICE-4', 'VOICE-5'],
                                              escape_cleared=True, chat_switch_cleared=True, pasted=combined),
        }
        self.save()
        (self.folder / 'transcripts-pasted.txt').write_text(combined)
        for name in ['transcripts-marked', 'transcripts-palette', 'transcripts-copied', 'transcripts-missing', 'transcripts-pasted']:
            (self.folder / (name + '.png')).write_bytes(b'\x89PNG\r\n\x1a\n' + b'x' * 11000)

    def save(self):
        for name, value in self.files.items():
            (self.folder / name).write_text(json.dumps(value))

    def test_exact_raw_transcripts_and_paste_pass(self):
        validator.check_transcript_copy(self.folder)

    def test_changed_words_missing_voice_and_reversed_order_fail(self):
        row = self.files['transcript-copy.json']
        original = row['actual']
        for broken in ('formatted summary', original.replace('Grüße', 'Grusse'), '\r\n\r\n'.join(reversed(original.split('\r\n\r\n')))):
            with self.subTest(broken=broken):
                row['actual'] = broken
                self.save()
                with self.assertRaises(AssertionError):
                    validator.check_transcript_copy(self.folder)

    def test_silent_missing_transcript_fails(self):
        self.files['transcript-missing.json']['title'] = 'Copied 2 transcripts'
        self.save()
        with self.assertRaises(AssertionError):
            validator.check_transcript_copy(self.folder)

    def test_chat_selection_leak_fails(self):
        self.files['transcript-selection.json']['chat_switch_cleared'] = False
        self.save()
        with self.assertRaises(AssertionError):
            validator.check_transcript_copy(self.folder)

    def test_wrong_pasted_text_fails(self):
        (self.folder / 'transcripts-pasted.txt').write_text('wrong application text')
        with self.assertRaises(AssertionError):
            validator.check_transcript_copy(self.folder)


if __name__ == '__main__':
    unittest.main()
