import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BREAKING_COMMIT = "31c5dfa4c86ebe64eb56f60fdb4ce938693a7466"


def function(source, name):
    start = source.index(f"pub fn {name}(")
    end = source.index("\n}\n", start) + 3
    return source[start:end]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zig", required=True)
    args = parser.parse_args()
    source = (ROOT / "src/dictation_policy.zig").read_text()
    historical = subprocess.check_output(
        ["git", "show", f"{BREAKING_COMMIT}:src/dictation_policy.zig"],
        cwd=ROOT, text=True,
    )
    old = function(historical, "transcribe").replace("pub fn transcribe(", "pub fn transcribeFile(", 1)
    mutated = source.replace(function(source, "transcribeFile"), old, 1)
    with tempfile.TemporaryDirectory(prefix="voice-regression-") as directory:
        path = Path(directory) / "policy.zig"
        for label, content in (("fixed", source), ("historical", mutated)):
            path.write_text(content)
            result = subprocess.run(
                [args.zig, "test", str(path), "--test-filter", "ISSUE-517"],
                cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            )
            print(f"{label}:\n{result.stdout}", flush=True)
            if label == "fixed":
                assert result.returncode == 0, "fixed voice-note logic failed"
                assert "All 2 tests passed" in result.stdout, "regression tests did not execute"
            else:
                assert result.returncode != 0, "historical voice-note logic escaped regression test"
                assert "FAIL (NoSpeech)" in result.stdout, "negative control did not fail on empty recognition"
                assert "stored own Ogg falls back" in result.stdout, "wrong regression failed"
    worker = (ROOT / "src/dictation.zig").read_text()
    ui = (ROOT / "src/main.zig").read_text()
    assert "dictation_policy.transcribeFile(Transport{" in worker
    assert "lit(dictation_policy.multilingual_path)" in worker
    assert "self.failure = err;" in worker
    assert "poll: failed reason={s}" in ui
    assert "if (message.transcript_state == .failed) {" in ui
    assert "message.transcript_state == .loading or message.transcript_state == .failed" in ui
    assert 'else lit("Transcription failed")' in ui
    print("ISSUE-517 fixed tests pass and historical NoSpeech regression is caught", flush=True)


if __name__ == "__main__":
    main()
