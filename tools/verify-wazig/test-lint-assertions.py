import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location('lint_assertions', Path(__file__).with_name('lint-assertions.py'))
lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint)


class ProxyAssertions(unittest.TestCase):
    def check_script(self, text, allowed=()):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'journey-example.ps1').write_text(text)
            return lint.check(root, allowed)

    def test_past_hub_false_positive_fails(self):
        text = "$null = Wait-Until { (Read-Edit (Get-Edit (Get-Window $session) '1032')) -ne '@' } 'mention inserted' 15"
        self.assertIn('changed or nonempty text alone', self.check_script(text)[0])

    def test_exit_and_success_proxies_fail(self):
        for expression in ('$LASTEXITCODE -eq 0', '$exitCode -eq 0', '$child.ExitCode -eq 0', '$response.ok', '$?', '-not $errors', '$errors.Count -eq 0'):
            with self.subTest(expression=expression):
                self.assertTrue(self.check_script(f'Assert-That ({expression}) "passed"'))
        self.assertTrue(self.check_script("if ($LASTEXITCODE -ne 0) { throw 'failed' }"))

    def test_changed_and_nonempty_text_fail(self):
        for expression in ('$afterText -ne $beforeText', "$text -ne ''", '$reply.previewText.Length -gt 0'):
            with self.subTest(expression=expression):
                self.assertTrue(self.check_script(f'Wait-Until {{ {expression} }} "changed"'))

    def test_exact_text_payload_and_pixels_pass(self):
        for expression in ("(Read-Edit $compose) -ceq '<@UFIXTURE>'", "$request.body.text -ceq '<@UFIXTURE> hello'", '$pixels.blue -ge 6', '$frame.visible -and $frame.width -gt 0'):
            with self.subTest(expression=expression):
                self.assertEqual([], self.check_script(f'Assert-That ({expression}) "visible"'))

    def test_proxy_conjunctions_and_validator_exit_fail(self):
        self.assertTrue(self.check_script('Assert-That (($text -ne $before) -and ($LASTEXITCODE -eq 0)) "passed"'))
        self.assertTrue(self.check_script('Wait-Until { & python "$PSScriptRoot/validator.py" $folder; $LASTEXITCODE -eq 0 } "passed"'))

    def test_legitimate_state_and_http_checks_pass(self):
        for expression in ('$reply.StatusCode -eq 401', '$null -ne $before.$field -and $null -ne $after.$field', '$state.reply.preview -ceq $expectedPreview'):
            with self.subTest(expression=expression):
                self.assertEqual([], self.check_script(f'Assert-That ({expression}) "observed"'))

    def test_nested_multiline_assertion_and_quoted_braces(self):
        text = "Wait-Until {\n (Read-Edit (Get-Edit $window '1032')) -ceq 'a } b'\n} 'exact text'"
        self.assertEqual([(1, "(Read-Edit (Get-Edit $window '1032')) -ceq 'a } b'")], list(lint.assertions(text)))

    def test_harness_flag_is_not_an_exception(self):
        self.assertTrue(self.check_script('Assert-That ($LASTEXITCODE -eq 0) "passed" -Harness'))

    def test_containment_and_wildcard_containment_fail(self):
        for expression in ("(Read-Edit $edit).Contains('x')", "$row.text.Contains('done')", '($pins.PinnedChats -like "*$id*")'):
            with self.subTest(expression=expression):
                self.assertTrue(self.check_script(f'Assert-That ({expression}) "seen"'))

    def test_containment_guarded_or_compared_passes(self):
        for expression in ("(Test-Path $draft) -and (Get-Content $draft -Raw).Contains('x')",
                           "-not $log.Contains('WrongChat')",
                           "$line.StartsWith('Offline') -and $line.EndsWith('last sync 08:45')"):
            with self.subTest(expression=expression):
                self.assertEqual([], self.check_script(f'Assert-That ({expression}) "seen"'))

    def test_exact_reasoned_exception_and_stale_exception(self):
        allowed = [dict(file='journey-example.ps1', assertion='$LASTEXITCODE -eq 0', reason='The external screenshot validator checks the visible popup pixels and exact payload.')]
        self.assertEqual([], self.check_script('Assert-That ($LASTEXITCODE -eq 0) "validated"', allowed))
        self.assertIn('stale proxy exception', self.check_script('Assert-That ($pixels -ge 6) "visible"', allowed)[0])
        self.assertTrue(self.check_script('Assert-That ($LASTEXITCODE -eq 0) "validated"', [dict(allowed[0], reason='fine')]))


if __name__ == '__main__':
    unittest.main()
