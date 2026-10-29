from pathlib import Path
import json
import runpy
import tempfile
import unittest


CHECK = runpy.run_path(str(Path(__file__).parent / 'verify-wazig/check-reply-evidence.py'))['check_reply']


class ReplyEvidenceTests(unittest.TestCase):
    def fixture(self, root):
        def write(name, value):
            (root / name).write_text(json.dumps(value))

        write('session.json', dict(sha256='fixture-binary', commit='fixture-commit'))
        write('result.json', dict(feature='reply', status='passed'))
        write('side-effects.json', dict(pending_sends=0, pending_archives=0,
                                       production_preferences_absent=True, whatsapp_store_absent=True))
        requests = []
        for provider, chat in [('whatsapp', 'fixture-beta'), ('slack', 'fixture-alpha')]:
            for phase in ['before', 'replying', 'sent', 'jumped']:
                state = dict(selected=dict(id=chat, provider=provider), reply=dict(id='REPLY-ORIGINAL',
                             sender='Fixture Sender', preview='First words of the original'), reply_flash='REPLY-ORIGINAL')
                write(f'{provider}-{phase}.state.json', state)
                (root / f'{provider}-{phase}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + phase.encode() * 10001)
            write(f'{provider}-sent.messages.json', dict(messages=[dict(from_me=True,
                  quoted_msg_id='REPLY-ORIGINAL', quote_line=[10, 10, 110, 30], bubble=[10, 36, 110, 80])]))
            requests.append(dict(wire_path='/v1/wazig/send', status=200, authorized=True,
                                 body=dict(chat=chat, reply_to='REPLY-ORIGINAL', text=f'Synthetic {provider} reply')))
        (root / 'bridge-requests.jsonl').write_text('\n'.join(map(json.dumps, requests)))

    def test_complete_two_provider_reply_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            CHECK(root)

    def test_rejects_missing_preview_wrong_target_and_inside_bubble(self):
        for name, change in [
            ('whatsapp-replying.state.json', lambda row: row['reply'].update(id='')),
            ('slack-sent.messages.json', lambda row: row['messages'][0].update(quoted_msg_id='wrong')),
            ('whatsapp-sent.messages.json', lambda row: row['messages'][0].update(quote_line=[10, 40, 110, 60])),
            ('side-effects.json', lambda row: row.update(pending_sends=1)),
        ]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.fixture(root)
                path = root / name
                data = json.loads(path.read_text())
                change(data)
                path.write_text(json.dumps(data))
                with self.assertRaises(AssertionError):
                    CHECK(root)


if __name__ == '__main__':
    unittest.main()
