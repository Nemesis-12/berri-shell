"""Usage readings keep percentages and recover from failed requests."""
import importlib.util
import json
import contextlib
import subprocess
import sys
import tempfile
import textwrap
import time
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("agent_usage", Path(__file__).with_name("agent-usage.py"))
usage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usage)


# Serve synthetic usage and record only the test authorization header.
@contextlib.contextmanager
def usage_server(status=200, location=None):
    authorization = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            authorization.append(self.headers.get("Authorization"))
            self.send_response(status)
            if location:
                self.send_header("Location", location)
            self.end_headers()
            if status == 200:
                self.wfile.write(json.dumps({"five_hour": {
                    "utilization": 0.5, "resets_at": "2030-01-01T00:00:00Z",
                }}).encode())

        def log_message(self, *args):
            pass

    with HTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01})
        thread.start()
        try:
            yield f"http://127.0.0.1:{server.server_port}/usage", authorization
        finally:
            server.shutdown()
            thread.join(timeout=1)


class PercentageTests(unittest.TestCase):
    def test_usage_percentage_keeps_small_values(self):
        reset = "2030-01-01T00:00:00Z"
        for percent in (0, 0.5, 1, 1.1, 100):
            with self.subTest(percent=percent):
                self.assertEqual(usage.claude_bucket({"utilization": percent, "resets_at": reset}),
                                 {"percent": percent, "resetsAt": reset})
                self.assertEqual(usage.codex_window({"usedPercent": percent, "resetsAt": 1893456000}),
                                 {"percent": percent, "resetsAt": "2030-01-01T00:00:00+00:00"})


class ClaudeRequestTests(unittest.TestCase):
    def test_redirect_keeps_authorization_at_original_server(self):
        login = json.dumps({"claudeAiOauth": {"accessToken": "synthetic-test-authorization"}})
        bucket = {"percent": 12.5, "resetsAt": "2030-01-01T00:00:00Z"}
        cache = {"claude": {"session": bucket, "weekly": None}}
        with usage_server() as (target, target_authorization), \
             usage_server(302, target.replace("127.0.0.1", "localhost")) as (source, source_authorization), \
             patch.object(Path, "read_text", return_value=login), \
             patch.object(usage, "USAGE_ENDPOINT", source):
            result = usage.claude_usage(cache)
            self.assertEqual(source_authorization, ["Bearer synthetic-test-authorization"])
            self.assertEqual(target_authorization, [])
            self.assertEqual(result, {"session": bucket, "weekly": None})
            with patch.object(usage, "USAGE_ENDPOINT", target):
                self.assertEqual(usage.claude_usage({}), {"session": {
                    "percent": 0.5, "resetsAt": "2030-01-01T00:00:00Z",
                }, "weekly": None})
            self.assertEqual(target_authorization, ["Bearer synthetic-test-authorization"])


class CodexRequestTests(unittest.TestCase):
    def test_complete_responses_accept_notifications_and_split_bytes(self):
        child = textwrap.dedent('''\
            import json
            import sys
            import time
            for line in sys.stdin:
                request = json.loads(line)
                response = json.dumps({"id": request["id"], "result": "café"}, ensure_ascii=False).encode()
                sys.stdout.buffer.write(b'not json\\n[]\\n{"method":"notice"}\\n' + response[:-3])
                sys.stdout.buffer.flush()
                time.sleep(0.01)
                sys.stdout.buffer.write(response[-3:] + b'\\n')
                sys.stdout.buffer.flush()
        ''')
        with subprocess.Popen([sys.executable, "-c", child], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, text=True) as proc:
            try:
                for request_id in (1, 2):
                    self.assertEqual(usage.rpc_request(proc, request_id, "read", timeout=0.1),
                                     {"id": request_id, "result": "café"})
            finally:
                proc.terminate()
                proc.wait(timeout=1)

    def test_partial_line_stops_request_and_child_before_deadline(self):
        scratch = Path(__file__).resolve().parent.parent / "scratchpad"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            child = Path(folder) / "codex"
            child.write_text(f"#!{sys.executable}\n" + textwrap.dedent('''\
                import json
                import signal
                import sys
                import time
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                request = json.loads(sys.stdin.readline())
                print(json.dumps({"id": request["id"], "result": {}}), flush=True)
                sys.stdin.readline()
                sys.stdin.readline()
                sys.stdout.write('{"id": 2, "result":')
                sys.stdout.flush()
                time.sleep(1)
            '''), encoding="utf-8")
            child.chmod(0o755)
            children = []
            start_child = subprocess.Popen
            request = usage.rpc_request

            # Run the real child and request with a shorter test deadline.
            def launch(*args, **kwargs):
                proc = start_child(*args, **kwargs)
                children.append(proc)
                return proc

            def short_request(*args, **kwargs):
                return request(*args, **{**kwargs, "timeout": 0.1})

            bucket = {"percent": 12.5, "resetsAt": "2030-01-01T00:00:00Z"}
            cache = {"codex": {"session": bucket, "weekly": None}}
            try:
                with patch.object(usage.shutil, "which", return_value=str(child)), \
                     patch.object(usage.subprocess, "Popen", side_effect=launch), \
                     patch.object(usage, "rpc_request", side_effect=short_request):
                    started = time.monotonic()
                    result = usage.codex_usage(cache)
                    elapsed = time.monotonic() - started
                self.assertEqual(result, {"session": bucket, "weekly": None})
                self.assertEqual(len(children), 1)
                self.assertIsNotNone(children[0].poll(), "child is still running")
                self.assertLessEqual(elapsed, 0.6)
            finally:
                for proc in children:
                    if proc.poll() is None:
                        proc.kill()
                    proc.wait(timeout=2)
                    proc.stdin.close()
                    proc.stdout.close()


if __name__ == "__main__":
    unittest.main()
