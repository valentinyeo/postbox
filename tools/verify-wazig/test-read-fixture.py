from pathlib import Path
import runpy
import unittest


fixture = runpy.run_path(str(Path(__file__).with_name('fake-hub.py')))


class ReadFixtureShapes(unittest.TestCase):
    def test_newest_unread_does_not_erase_older_read_message(self):
        handler = fixture['ReadTicksHandler'].__new__(fixture['ReadTicksHandler'])
        handler.path = '/v1/wazig/messages?chat=ticks-late%40s.whatsapp.net'
        handler.authorized = lambda: True
        responses = []
        handler.respond = lambda status, rows: responses.append((status, rows))
        handler.do_GET()
        status, rows = responses[0]
        self.assertEqual(200, status)
        self.assertEqual(['tick-own', 'tick-in', 'tick-read'], [row['MsgID'] for row in rows])
        self.assertTrue(rows[0]['FromMe'])
        self.assertEqual(0, rows[0]['ReadBy'])
        self.assertTrue(rows[2]['FromMe'])
        self.assertEqual(1, rows[2]['ReadBy'])
        self.assertLess(rows[2]['Timestamp'], rows[0]['Timestamp'])
        self.assertTrue(all(row['ChatJID'] == 'ticks-late@s.whatsapp.net' for row in rows))


if __name__ == '__main__':
    unittest.main()
