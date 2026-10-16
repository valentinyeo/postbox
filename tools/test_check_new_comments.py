import unittest

from check_new_comments import find_new_comments

PAST_F353B40 = """diff --git a/src/child_process.zig b/src/child_process.zig
new file mode 100644
--- /dev/null
+++ b/src/child_process.zig
@@ -0,0 +1,4 @@
+const std = @import("std");
+
+// Serialize creation so Windows children cannot inherit another spawn's pipe handles.
+var spawn_mutex: std.Io.Mutex = .init;
"""


def diff(path, *lines):
    body = "".join("+" + line + "\n" for line in lines)
    return f"diff --git a/{path} b/{path}\n--- a/{path}\n+++ b/{path}\n@@ -1,0 +1,{len(lines)} @@\n{body}"


class FindNewComments(unittest.TestCase):
    def test_real_past_comment_fails(self):
        hits = find_new_comments(PAST_F353B40)
        self.assertEqual([(h[0], h[1]) for h in hits], [("src/child_process.zig", 3)])

    def test_zig_comment_kinds(self):
        hits = find_new_comments(diff("src/a.zig", "//! top", "/// doc", "const a = 1; // trailing"))
        self.assertEqual(len(hits), 3)

    def test_zig_strings_are_not_comments(self):
        hits = find_new_comments(diff("src/a.zig", 'const u = "https://example.com";', "    \\\\multi // line", "const c = '/';"))
        self.assertEqual(hits, [])

    def test_zig_fmt_directive_allowed(self):
        self.assertEqual(find_new_comments(diff("src/a.zig", "// zig fmt: off")), [])

    def test_hash_languages(self):
        hits = find_new_comments(diff("tools/x.py", "#!/usr/bin/env python3", "x = '#not'", "y = 1  # note"))
        self.assertEqual([h[1] for h in hits], [3])
        self.assertEqual(find_new_comments(diff("a.sh", 'echo "${#arr[@]} $#"', "# shellcheck disable=SC2086")), [])
        self.assertEqual(len(find_new_comments(diff("a.sh", "# explain"))), 1)

    def test_vendor_and_other_files_ignored(self):
        self.assertEqual(find_new_comments(diff("vendor/libwebp/a.c", "// upstream")), [])
        self.assertEqual(find_new_comments(diff("README.md", "# Title")), [])

    def test_removed_and_context_lines_ignored(self):
        text = "diff --git a/src/a.zig b/src/a.zig\n--- a/src/a.zig\n+++ b/src/a.zig\n@@ -1,1 +1,1 @@\n-// old\n+const a = 1;\n"
        self.assertEqual(find_new_comments(text), [])


if __name__ == "__main__":
    unittest.main()
