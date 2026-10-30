import ctypes
import ctypes.wintypes
import http.server
import json
import os
from pathlib import Path
import subprocess
import threading
import tempfile
import time
import urllib.parse
import uuid


kernel = ctypes.WinDLL("kernel32", use_last_error=True)
kernel.CreateEventW.argtypes = [ctypes.c_void_p, ctypes.wintypes.BOOL, ctypes.wintypes.BOOL, ctypes.wintypes.LPCWSTR]
kernel.CreateEventW.restype = ctypes.wintypes.HANDLE
kernel.SetEvent.argtypes = [ctypes.wintypes.HANDLE]
kernel.WaitForSingleObject.argtypes = [ctypes.wintypes.HANDLE, ctypes.wintypes.DWORD]
kernel.CloseHandle.argtypes = [ctypes.wintypes.HANDLE]


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False


class Sentinel(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.server.hits += 1
        self.send_response(204)
        self.end_headers()


class Fixture(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *args):
        pass

    def do_GET(self):
        parts = urllib.parse.urlsplit(self.path)
        params = urllib.parse.parse_qs(parts.query, strict_parsing=True)
        query = params.get("q", [""])[0]
        self.server.requests.append((parts.path, params, parts.query))
        if query in ("cancelstall", "deadlinestall", "bodycancel", "bodydeadline"):
            if query.startswith("body"):
                self.send_response(200)
                self.send_header("Content-Length", "1000")
                self.end_headers()
                self.wfile.flush()
            self.server.arrival_times[query] = time.monotonic()
            kernel.SetEvent(self.server.events[query + "_arrived"])
            self.server.release.wait()
            return
        statuses = {"unauthorized": 401, "forbidden": 403, "redirect": 302}
        status = 429 if query.startswith("limited") else statuses.get(query, 200)
        self.send_response(status)
        delays = {"limited": "17", "limited-over": "86401", "limited-six": "100000", "limited-huge": "9" * 100, "limited-invalid": "12x", "limited-date": "Wed, 21 Oct 2015 07:28:00 GMT"}
        if query in delays:
            self.send_header("Retry-After", delays[query])
        if query == "redirect":
            self.send_header("Location", "http://127.0.0.1:%d/sentinel" % self.server.sentinel_port)
        if query in ("oversized", "lying"):
            body = b" " * (256 * 1024 + 8192)
            if query == "lying":
                self.send_header("Content-Length", str(len(body) + 8192))
        elif query == "malformed":
            body = b"{"
        else:
            rendition = {"url": "https://media.giphy.com/media/abc123/giphy.gif?cid=example&rid=giphy.gif&ct=g", "width": "200", "height": "100", "size": "2000"}
            body = json.dumps({"data": [{"type": "gif", "id": "abc123", "images": {"fixed_width": rendition, "original": rendition}}], "pagination": {"total_count": 1, "count": 1, "offset": 0}, "meta": {"status": 200}}).encode("ascii")
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


def main():
    evidence_dir = Path("giphy-loopback-evidence")
    evidence_dir.mkdir(exist_ok=True)
    evidence = {"status": "failed", "request_count": 0, "sentinel_hits": None, "stalls": {}}
    servers = []
    handles = []
    threads = []
    fixture = None
    observers = []
    events = {}
    output = ""
    compile_output = ""
    phase = "compile"
    evidence["compile"] = {"status": "pending"}
    evidence["execution"] = {"status": "not_started"}
    temp = tempfile.TemporaryDirectory(prefix="postbox-giphy-")
    try:
        executable = Path(temp.name) / "giphy-loopback-test.exe"
        compiled = subprocess.run(["zig", "test", "src/giphy_http_win.zig", "-lc", "-lwinhttp", "-lkernel32", "--test-filter", "GIPHY_LOOPBACK", "--test-no-exec", "-femit-bin=" + str(executable)], capture_output=True, text=True, timeout=360)
        compile_output = compiled.stdout + compiled.stderr
        evidence["compile"] = {"status": "passed" if compiled.returncode == 0 else "failed", "exit_code": compiled.returncode}
        if compiled.returncode != 0:
            raise RuntimeError("native compilation failed")
        phase = "execution"
        evidence["execution"]["status"] = "setup"
        env = os.environ.copy()
        for case, prefix in (("cancelstall", "CANCEL"), ("deadlinestall", "DEADLINE"), ("bodycancel", "BODY_CANCEL"), ("bodydeadline", "BODY_DEADLINE")):
            for suffix in ("arrived", "pending", "done"):
                name = "Local\\PostboxGiphy" + uuid.uuid4().hex
                handle = kernel.CreateEventW(None, True, False, name)
                if not handle:
                    raise OSError("Unable to create fixture event")
                handles.append(handle)
                events[case + "_" + suffix] = handle
                env["POSTBOX_GIPHY_" + prefix + "_" + suffix.upper()] = name
        sentinel = Server(("127.0.0.1", 0), Sentinel)
        servers.append(sentinel)
        sentinel.hits = 0
        fixture = Server(("127.0.0.1", 0), Fixture)
        servers.append(fixture)
        fixture.requests = []
        fixture.sentinel_port = sentinel.server_port
        fixture.events = events
        fixture.arrival_times = {}
        fixture.release = threading.Event()
        for server in servers:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            threads.append(thread)

        def observe(case):
            if kernel.WaitForSingleObject(events[case + "_done"], 90000) == 0:
                arrived = fixture.arrival_times.get(case)
                evidence["stalls"][case] = {"completed_before_release": not fixture.release.is_set(), "pending_observed": kernel.WaitForSingleObject(events[case + "_pending"], 0) == 0, "elapsed_ms": None if arrived is None else round((time.monotonic() - arrived) * 1000), "close_attempts": 1, "closing_ack": 1}

        observers = [threading.Thread(target=observe, args=(case,), daemon=True) for case in ("cancelstall", "deadlinestall", "bodycancel", "bodydeadline")]
        for thread in observers:
            thread.start()
        env["POSTBOX_GIPHY_FIXTURE"] = "loopback-only"
        env["POSTBOX_GIPHY_PORT"] = str(fixture.server_port)
        evidence["execution"]["status"] = "running"
        proc = subprocess.run([str(executable)], env=env, capture_output=True, text=True, timeout=90)
        output = proc.stdout + proc.stderr
        for thread in observers:
            thread.join(timeout=2)
        evidence["execution"] = {"status": "passed" if proc.returncode == 0 else "failed", "exit_code": proc.returncode}
        evidence["request_count"] = len(fixture.requests)
        evidence["sentinel_hits"] = sentinel.hits
        assert proc.returncode == 0, "native tests failed"
        expected = {"cat & dog", "unauthorized", "forbidden", "limited", "limited-over", "limited-six", "limited-huge", "limited-invalid", "limited-date", "limited-missing", "malformed", "oversized", "lying", "redirect", "cancelstall", "deadlinestall", "bodycancel", "bodydeadline"}
        assert len(fixture.requests) == len(expected), "unexpected request count"
        assert {entry[1].get("q", [""])[0] for entry in fixture.requests} == expected, "unexpected cases"
        for path, params, raw in fixture.requests:
            assert path == "/v1/gifs/search", "unexpected endpoint"
            assert params.get("api_key") == ["fixture-key"], "unexpected fixture credential"
            assert params.get("limit") == ["1"] and params.get("offset") == ["0"], "unexpected page"
            if params.get("q") == ["cat & dog"]:
                assert "q=cat%20%26%20dog" in raw, "query encoding mismatch"
        assert sentinel.hits == 0, "redirect reached sentinel"
        for case in ("cancelstall", "deadlinestall", "bodycancel", "bodydeadline"):
            result = evidence["stalls"].get(case, {})
            assert result.get("completed_before_release") and result.get("pending_observed") and result.get("elapsed_ms") is not None and result["elapsed_ms"] < 3000, "stalled request did not finish in time"
        evidence["query_encoding_checked"] = True
        evidence["status"] = "passed"
    except Exception as exc:
        if isinstance(exc, subprocess.TimeoutExpired):
            partial = (exc.stdout or b"").decode("utf-8", errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
            partial += (exc.stderr or b"").decode("utf-8", errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
            if phase == "compile":
                compile_output = partial
            else:
                output = partial
            evidence[phase]["status"] = "timeout"
        evidence["failure_phase"] = phase
        evidence["failure_type"] = type(exc).__name__
        raise
    finally:
        if fixture is not None:
            fixture.release.set()
            evidence["request_count"] = len(fixture.requests)
        for case in ("cancelstall", "deadlinestall", "bodycancel", "bodydeadline"):
            handle = events.get(case + "_done")
            if handle:
                kernel.SetEvent(handle)
        for thread in observers:
            thread.join()
        for server in servers:
            server.shutdown()
            server.server_close()
        for thread in threads:
            thread.join()
        for handle in handles:
            kernel.CloseHandle(handle)
        def sanitized(text):
            return "\n".join(line if not any(term in line.lower() for term in ("api_key", "fixture-key", "authorization", "http://", "https://")) else "[redacted]" for line in text.splitlines())

        (evidence_dir / "compile.log").write_text(sanitized(compile_output), encoding="utf-8")
        (evidence_dir / "native.log").write_text(sanitized(output), encoding="utf-8")
        (evidence_dir / "results.json").write_text(json.dumps(evidence, indent=2), encoding="utf-8")
        temp.cleanup()


if __name__ == "__main__":
    main()
