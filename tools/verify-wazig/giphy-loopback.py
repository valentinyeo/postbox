import http.server
import json
import os
import subprocess
import threading
import time
import urllib.parse


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
        if query == "slow":
            time.sleep(1)
        statuses = {"unauthorized": 401, "forbidden": 403, "limited": 429, "redirect": 302}
        status = statuses.get(query, 200)
        self.send_response(status)
        if query == "limited":
            self.send_header("Retry-After", "17")
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
    sentinel = Server(("127.0.0.1", 0), Sentinel)
    sentinel.hits = 0
    fixture = Server(("127.0.0.1", 0), Fixture)
    fixture.requests = []
    fixture.sentinel_port = sentinel.server_port
    threads = [threading.Thread(target=s.serve_forever, daemon=True) for s in (sentinel, fixture)]
    for thread in threads:
        thread.start()
    try:
        env = os.environ.copy()
        env["POSTBOX_GIPHY_FIXTURE"] = "loopback-only"
        env["POSTBOX_GIPHY_PORT"] = str(fixture.server_port)
        subprocess.run(["zig", "test", "src/giphy_http_win.zig", "-lc", "-lwinhttp", "-lkernel32", "--test-filter", "GIPHY_LOOPBACK"], env=env, check=True)
        expected = {"cat & dog", "unauthorized", "forbidden", "limited", "malformed", "oversized", "lying", "redirect", "slow"}
        assert len(fixture.requests) == len(expected), "unexpected request count"
        assert {entry[1].get("q", [""])[0] for entry in fixture.requests} == expected, "unexpected cases"
        for path, params, raw in fixture.requests:
            assert path == "/v1/gifs/search", "unexpected endpoint"
            assert params.get("api_key") == ["fixture-key"], "unexpected fixture credential"
            assert params.get("limit") == ["1"] and params.get("offset") == ["0"], "unexpected page"
            if params.get("q") == ["cat & dog"]:
                assert "q=cat%20%26%20dog" in raw, "query encoding mismatch"
        assert sentinel.hits == 0, "redirect reached sentinel"
        print("Native loopback cases passed; redirect sentinel received zero requests.")
    finally:
        for server in (fixture, sentinel):
            server.shutdown()
            server.server_close()
        for thread in threads:
            thread.join()


if __name__ == "__main__":
    main()
