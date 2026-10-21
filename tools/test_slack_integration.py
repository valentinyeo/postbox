import argparse
import base64
from contextlib import contextmanager
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import socket
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
from urllib.parse import parse_qs, urlencode, urlsplit


ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ("list", "history", "send", "live", "two_workspaces", "oauth_pkce")
SCOPES = "channels:read,channels:history,groups:read,groups:history,im:read,im:history,mpim:read,mpim:history,users:read,chat:write,files:read,files:write,reactions:read,channels:write,groups:write,im:write,mpim:write"
REDIRECT = "http://localhost:53682/slack/oauth/callback"
CHANNEL = "C0000000001"
TS = "1700000000.000001"
CLIENT_MSG_ID = "00000000-0000-4000-8000-000000000001"
CODE = "example-code+&="


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def parameters(encoded):
    fields = parse_qs(encoded, keep_blank_values=True, strict_parsing=True)
    require(all(len(values) == 1 for values in fields.values()), "duplicate parameter")
    return {key: values[0] for key, values in fields.items()}


def history_item(ts=TS, text="Example history", thread=False):
    return {
        "type": "message", "ts": ts, "user": "U0000000002", "text": text,
        "reply_count": 1 if ts == TS else 0,
        "reactions": [{"name": "thumbsup", "count": 1, "users": ["U0000000001"]}],
        **({"thread_ts": TS} if thread else {}),
    }


class State:
    def __init__(self, scenario):
        self.scenario = scenario
        self.requests = []
        self.failures = []
        self.ack_verified = threading.Event()
        self.ws_finished = threading.Event()
        self.challenge = None
        self.state = None
        self.http_url = None
        self.ws_url = None

    def token_response(self, rotated=False):
        return {
            "ok": True, "team": {"id": "T0000000001", "name": "Example Workspace"},
            "access_token": "bot-fixture-not-the-user",
            "authed_user": {
                "id": "U0000000001", "access_token": "user-fixture-rotated" if rotated else "user-fixture-1",
                "refresh_token": "refresh-fixture-rotated" if rotated else "refresh-fixture-1",
                "expires_in": 3600, "scope": SCOPES,
            },
        }


class HTTPHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.dispatch()

    def do_POST(self):
        self.dispatch()

    def reply(self, body, status=200, location=None):
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain" if isinstance(body, str) else "application/json")
        self.send_header("Content-Length", str(len(data)))
        if location:
            self.send_header("Location", location)
        self.end_headers()
        self.wfile.write(data)

    def dispatch(self):
        state = self.server.state
        try:
            self.connection.settimeout(5)
            url = urlsplit(self.path)
            query = parameters(url.query) if url.query else {}
            data = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            state.requests.append((self.command, url.path))
            if url.path in ("/oauth/v2/authorize", "/slack/oauth/callback", "/api/oauth.v2.access"):
                require(state.scenario == "oauth_pkce", "OAuth in wrong scenario")
                require(self.headers.get("Authorization") is None, "OAuth must not send bearer token")
                return self.oauth(state, url.path, query, data)
            token = self.headers.get("Authorization")
            expected_token = "Bearer app-fixture" if url.path == "/api/apps.connections.open" else "Bearer user-fixture-1"
            if state.scenario == "two_workspaces":
                require(token in ("Bearer user-fixture-1", "Bearer user-fixture-2"), "workspace auth")
            else:
                require(token == expected_token, "bearer auth")
            if url.path == "/api/conversations.list":
                require(state.scenario == "list" and self.command == "GET" and not data, "list method/body")
                require(query.keys() == {"types", "limit", "cursor"}, "list query fields")
                require(query["types"] == "public_channel,private_channel,im,mpim" and query["limit"] == "2", "conversation types")
                if query["cursor"] == "":
                    require(state.requests == [("GET", url.path)], "first page order")
                    channels = [
                        {"id": CHANNEL, "name": "example-public", "is_member": True},
                        {"id": "G0000000001", "name": "example-private", "is_member": True, "is_private": True},
                    ]
                    cursor = "page+2/="
                else:
                    require(query["cursor"] == "page+2/=", "pagination cursor")
                    require(len(state.requests) == 2, "second page order")
                    channels = [
                        {"id": "D0000000001", "user": "U0000000002", "is_im": True},
                        {"id": "G0000000002", "name": "example-group-dm", "is_member": True, "is_mpim": True},
                    ]
                    cursor = ""
                return self.reply({"ok": True, "channels": channels, "response_metadata": {"next_cursor": cursor}})
            if url.path == "/api/users.list":
                require(state.scenario == "list" and self.command == "GET" and not query and not data, "users method/body")
                return self.reply({"ok": True, "members": [
                    {"id": "U0000000001", "profile": {"display_name": "Example Self"}},
                    {"id": "U0000000002", "profile": {"display_name": "Example User"}},
                ]})
            if url.path in ("/api/conversations.history", "/api/conversations.replies"):
                require(state.scenario in ("history", "two_workspaces") and self.command == "GET" and not data, "history method/body")
                replies = url.path.endswith("replies")
                require(query == ({"channel": CHANNEL, "ts": TS} if replies else {"channel": CHANNEL}), "history query")
                text = "Example team two" if token == "Bearer user-fixture-2" else "Example team one"
                return self.reply({"ok": True, "messages": [history_item(text=text, thread=replies), history_item("1700000001.000001", "Example reply", thread=replies)]})
            if url.path == "/api/chat.postMessage":
                require(state.scenario == "send" and self.command == "POST" and not query, "send method")
                require(self.headers.get_content_type() == "application/json", "send content type")
                require(json.loads(data) == {"channel": CHANNEL, "text": 'Example "message"\nline', "client_msg_id": CLIENT_MSG_ID, "thread_ts": TS}, "send body")
                return self.reply({"ok": True, "channel": CHANNEL, "ts": "1700000001.000001"})
            if url.path == "/api/apps.connections.open":
                require(state.scenario == "live" and self.command == "POST" and not query, "socket method")
                require(self.headers.get_content_type() == "application/json" and json.loads(data) == {}, "socket body")
                return self.reply({"ok": True, "url": state.ws_url})
            if url.path == "/api/auth.test":
                require(state.scenario == "two_workspaces" and self.command == "GET" and not query and not data, "auth method/body")
                return self.reply({"ok": True, "team_id": "T0000000002" if token == "Bearer user-fixture-2" else "T0000000001", "user_id": "U0000000001"})
            raise AssertionError("unexpected endpoint")
        except Exception as error:
            state.failures.append(str(error))
            self.reply({"ok": False, "error": "invalid_fixture_request"}, status=400)

    def oauth(self, state, path, query, data):
        if path == "/oauth/v2/authorize":
            require(self.command == "GET" and not data, "authorize method/body")
            require(query.keys() == {"client_id", "user_scope", "redirect_uri", "state", "code_challenge", "code_challenge_method"}, "authorize fields")
            require(query["client_id"] == "desktop-fixture" and query["user_scope"] == SCOPES, "authorize client/scopes")
            require(query["redirect_uri"] == REDIRECT and query["code_challenge_method"] == "S256", "authorize PKCE settings")
            require(re.fullmatch(r"[A-Za-z0-9_-]{43}", query["state"]) is not None, "state encoding")
            require(re.fullmatch(r"[A-Za-z0-9_-]{43}", query["code_challenge"]) is not None, "challenge encoding")
            state.challenge, state.state = query["code_challenge"], query["state"]
            return self.reply("", status=302, location=state.http_url + "/slack/oauth/callback?" + urlencode({"code": CODE, "state": state.state}))
        if path == "/slack/oauth/callback":
            require(self.command == "GET" and not data and query == {"code": CODE, "state": state.state}, "loopback redirect")
            return self.reply(self.requestline)
        require(self.command == "POST" and not query, "token method")
        require(self.headers.get_content_type() == "application/x-www-form-urlencoded", "token content type")
        fields = parameters(data.decode())
        if fields.get("grant_type") == "refresh_token":
            require(fields == {"grant_type": "refresh_token", "client_id": "desktop-fixture", "refresh_token": "refresh-fixture-1"}, "refresh body")
            return self.reply(state.token_response(rotated=True))
        require(fields.keys() == {"client_id", "code", "code_verifier", "redirect_uri", "grant_type"}, "token fields")
        require(fields["client_id"] == "desktop-fixture" and fields["code"] == CODE, "token client/code")
        require(fields["redirect_uri"] == REDIRECT and fields["grant_type"] == "authorization_code", "token grant/redirect")
        verifier = fields["code_verifier"]
        require(re.fullmatch(r"[A-Za-z0-9._~-]{43,128}", verifier) is not None, "verifier encoding")
        actual = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
        if actual != state.challenge:
            state.failures.append("wrong_verifier")
            return self.reply({"ok": False, "error": "invalid_code_verifier"})
        return self.reply(state.token_response())


def read_exact(stream, size):
    data = bytearray()
    while len(data) < size:
        part = stream.recv(size - len(data))
        if not part:
            raise EOFError("socket closed")
        data.extend(part)
    return bytes(data)


def send_frame(stream, text):
    data = text.encode()
    header = bytes([0x81, len(data)]) if len(data) < 126 else b"\x81\x7e" + struct.pack("!H", len(data))
    stream.sendall(header + data)


class WebSocketHandler(socketserver.BaseRequestHandler):
    def handle(self):
        state = self.server.state
        try:
            self.request.settimeout(2)
            with self.request.makefile("rb") as reader:
                require(reader.readline() == b"GET /socket?fixture=1 HTTP/1.1\r\n", "websocket request line")
                headers = {}
                while True:
                    line = reader.readline()
                    if line == b"\r\n":
                        break
                    require(line, "websocket header EOF")
                    name, value = line.decode().split(":", 1)
                    headers[name.lower()] = value.strip()
                require(headers.get("upgrade", "").lower() == "websocket", "websocket upgrade")
                require(headers.get("connection", "").lower() == "upgrade", "websocket connection")
                require(headers.get("sec-websocket-version") == "13", "websocket version")
                require(headers.get("host") == urlsplit(state.ws_url).netloc, "websocket host")
                key = headers["sec-websocket-key"]
                require(len(base64.b64decode(key, validate=True)) == 16, "websocket nonce")
                accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
                self.request.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n").encode())
                send_frame(self.request, json.dumps({
                    "type": "events_api", "envelope_id": "example-envelope-1",
                    "payload": {"type": "events_api", "team_id": "T0000000001", "event": {
                        "type": "message", "channel": CHANNEL, "ts": TS, "user": "U0000000002", "text": "Example live message",
                    }},
                }))
                try:
                    first, size = read_exact(self.request, 2)
                except (socket.timeout, EOFError):
                    state.failures.append("missing_ack")
                    return
                require(first == 0x81 and size & 0x80 and size & 0x7f < 126, "masked text ack")
                mask = read_exact(self.request, 4)
                payload = read_exact(self.request, size & 0x7f)
                ack = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
                require(json.loads(ack) == {"envelope_id": "example-envelope-1"}, "envelope ack")
                state.ack_verified.set()
                send_frame(self.request, "ack-verified")
        except Exception as error:
            state.failures.append(str(error))
        finally:
            state.ws_finished.set()


class WebSocketServer(socketserver.ThreadingTCPServer):
    daemon_threads = True


@contextmanager
def fake_slack(scenario):
    state = State(scenario)
    with ThreadingHTTPServer(("127.0.0.1", 0), HTTPHandler) as http, WebSocketServer(("127.0.0.1", 0), WebSocketHandler) as ws:
        http.state = ws.state = state
        state.http_url = f"http://127.0.0.1:{http.server_port}"
        state.ws_url = f"ws://127.0.0.1:{ws.server_address[1]}/socket?fixture=1"
        threads = [threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True) for server in (http, ws)]
        for thread in threads:
            thread.start()
        try:
            yield state
        finally:
            http.shutdown()
            ws.shutdown()
            for thread in threads:
                thread.join(timeout=5)
                require(not thread.is_alive(), "server thread shutdown")


def run_scenario(zig, cache, scenario, mutation="none"):
    with fake_slack(scenario) as state:
        command = [zig, "run", str(ROOT / "src/slack_integration_test.zig"), "--cache-dir", str(cache / "local"), "--global-cache-dir", str(cache / "global"), "--", state.http_url, scenario, mutation]
        result = subprocess.run(command, cwd=cache, capture_output=True, text=True, timeout=180)
        if scenario == "live":
            require(state.ws_finished.wait(timeout=5), "websocket session completed")
        if mutation != "none":
            expected_error = "OAuthFailed" if mutation == "wrong_verifier" else "EndOfStream"
            require(result.returncode != 0 and "error: " + expected_error in result.stderr, f"negative control {mutation} did not fail a runtime assertion:\n{result.stdout}{result.stderr}")
            require(state.failures == [mutation], f"negative control {mutation} failed for wrong reason: {state.failures}")
            require(not state.ack_verified.is_set(), "negative control unexpectedly acknowledged")
            return
        require(result.returncode == 0, f"{scenario} Zig harness failed ({state.failures}):\n{result.stdout}{result.stderr}")
        require(not state.failures, f"{scenario} fake server rejected request: {state.failures}")
        expected_requests = {
            "list": [("GET", "/api/conversations.list")] * 2 + [("GET", "/api/users.list")],
            "history": [("GET", "/api/conversations.history"), ("GET", "/api/conversations.replies")],
            "send": [("POST", "/api/chat.postMessage")],
            "live": [("POST", "/api/apps.connections.open")],
            "two_workspaces": [("GET", "/api/auth.test"), ("GET", "/api/conversations.history")] * 2,
            "oauth_pkce": [("GET", "/oauth/v2/authorize"), ("GET", "/slack/oauth/callback")] + [("POST", "/api/oauth.v2.access")] * 2,
        }
        require(state.requests == expected_requests[scenario], f"{scenario} missing or unexpected requests: {state.requests}")
        if scenario == "live":
            require(state.ack_verified.is_set(), "server did not verify ack")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache-dir", required=True, type=Path)
    parser.add_argument("--zig", default=os.environ.get("ZIG", str(Path.home() / ".local/zig-0.16.0/zig") if (Path.home() / ".local/zig-0.16.0/zig").is_file() else "zig"))
    args = parser.parse_args()
    cache = args.cache_dir.resolve()
    require(cache != ROOT and ROOT not in cache.parents, "cache directory must be outside the repository")
    cache.mkdir(parents=True, exist_ok=True)
    zig = args.zig
    if os.path.sep in zig:
        zig = str(Path(zig).resolve())
    require(subprocess.check_output([zig, "version"], text=True).strip() == "0.16.0", "Zig 0.16.0 required")
    with tempfile.TemporaryDirectory(prefix="slack-fake-", dir=cache) as scratch:
        directory = Path(scratch)
        for scenario in SCENARIOS:
            run_scenario(zig, directory, scenario)
        run_scenario(zig, directory, "oauth_pkce", "wrong_verifier")
        run_scenario(zig, directory, "live", "missing_ack")
    for scenario in SCENARIOS:
        print("SLACK_FAKE_OK " + scenario)


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, subprocess.SubprocessError, OSError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
