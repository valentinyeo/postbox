import unittest

from check_hub_only import negative_controls, verify_source


class HubOnlyTest(unittest.TestCase):
    def test_inline_and_transitive_connector_fixtures(self):
        negative_controls()

    def test_payload_data_and_host_validation_are_not_connectors(self):
        verify_source('if (std.mem.eql(u8, host, "slack.com")) return true;')
        verify_source('if (std.mem.endsWith(u8, host, ".slack.com")) return true;')
        verify_source('test "payload parsing" { const host = "slack.com"; }')

    def test_connector_after_test_block_is_still_rejected(self):
        with self.assertRaisesRegex(AssertionError, 'desktop direct connector remains'):
            verify_source('test "braces {" { const text = "}"; } fn connect() void { td_json_client_create(); }')

    def test_test_name_in_string_does_not_hide_connector(self):
        with self.assertRaisesRegex(AssertionError, 'desktop direct connector remains'):
            verify_source('const text = "test"; fn connect() void { td_json_client_create(); }')

    def test_retired_import_with_whitespace_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, 'telegram.zig'):
            verify_source('const connector = @import ( "telegram.zig" );')


if __name__ == '__main__':
    unittest.main()
