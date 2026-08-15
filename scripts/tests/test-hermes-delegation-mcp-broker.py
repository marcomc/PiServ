#!/usr/bin/env python3
"""Exercise the rendered credential-isolating Home Assistant MCP broker."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def load_broker(broker_path: Path):
    """Import the rendered broker without executing its stdio entry point."""
    spec = importlib.util.spec_from_file_location("rendered_ha_mcp_broker", broker_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load broker: {broker_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HomeAssistantFixture(BaseHTTPRequestHandler):
    """Record one broker request and reply with a compact JSON-RPC result."""

    received_headers: dict[str, str] = {}
    received_body: bytes = b""
    request_count = 0

    def do_POST(self) -> None:  # noqa: N802
        type(self).request_count += 1
        content_length = int(self.headers["Content-Length"])
        type(self).received_headers = dict(self.headers.items())
        type(self).received_body = self.rfile.read(content_length)
        request = json.loads(type(self).received_body)
        body = json.dumps(
            {"jsonrpc": "2.0", "id": request["id"], "result": {"ok": True}}
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Mcp-Session-Id", "fixture-session")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


class BrokerTests(unittest.TestCase):
    """Verify fixed-target forwarding never returns the upstream bearer token."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), HomeAssistantFixture)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.broker = load_broker(Path(sys.argv[1]))
        cls.broker.TARGET_URL = f"http://127.0.0.1:{cls.server.server_port}/api/mcp"

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)

    def test_forwards_only_to_fixed_target_with_broker_owned_token(self) -> None:
        messages, session_id = self.broker.forward_frame(
            b'{"jsonrpc":"2.0","id":7,"method":"tools/list","params":{}}',
            "fixture-bearer-token",
            None,
        )
        self.assertEqual(session_id, "fixture-session")
        self.assertEqual(
            messages,
            ['{"jsonrpc": "2.0", "id": 7, "result": {"ok": true}}'],
        )
        self.assertEqual(
            HomeAssistantFixture.received_headers["Authorization"],
            "Bearer fixture-bearer-token",
        )
        self.assertNotIn("fixture-bearer-token", "\n".join(messages))
        self.assertEqual(
            json.loads(HomeAssistantFixture.received_body)["method"], "tools/list"
        )

    def test_rejects_an_oversized_frame_before_upstream_connection(self) -> None:
        with self.assertRaisesRegex(self.broker.BrokerError, "frame exceeded"):
            self.broker.forward_frame(
                b"x" * (self.broker.MAX_FRAME_BYTES + 1),
                "fixture-bearer-token",
                None,
            )

    def test_main_rejects_an_oversized_stdin_line_before_upstream_connection(self) -> None:
        request_count_before = HomeAssistantFixture.request_count
        runner = """
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("broker", sys.argv[1])
broker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(broker)
broker.TARGET_URL = sys.argv[2]
raise SystemExit(broker.main())
"""
        environment = os.environ.copy()
        environment[self.broker.TOKEN_ENV_VAR] = "fixture-bearer-token"
        result = subprocess.run(
            [
                sys.executable,
                "-c",
                runner,
                str(Path(sys.argv[1])),
                f"http://127.0.0.1:{self.server.server_port}/api/mcp",
            ],
            input=b"x" * (self.broker.MAX_FRAME_BYTES + 1) + b"\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=environment,
            timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8"))
        self.assertIn(b"Home Assistant MCP broker rejected the request", result.stdout)
        self.assertNotIn(b"fixture-bearer-token", result.stdout)
        self.assertEqual(HomeAssistantFixture.request_count, request_count_before)

    def test_rejects_an_unreachable_dependency_without_a_fallback(self) -> None:
        original_connection = self.broker.HTTPConnection
        attempted_connections = 0

        class UnreachableConnection:
            def __init__(self, *args: object, **kwargs: object) -> None:
                nonlocal attempted_connections
                attempted_connections += 1

            def request(self, *args: object, **kwargs: object) -> None:
                raise OSError("fixture dependency unavailable")

            def close(self) -> None:
                return

        self.broker.TARGET_URL = "http://dependency.invalid/api/mcp"
        self.broker.HTTPConnection = UnreachableConnection
        try:
            with self.assertRaisesRegex(self.broker.BrokerError, "request failed"):
                self.broker.forward_frame(
                    b'{"jsonrpc":"2.0","id":8,"method":"tools/list","params":{}}',
                    "fixture-bearer-token",
                    None,
                )
        finally:
            self.broker.HTTPConnection = original_connection
            self.broker.TARGET_URL = (
                f"http://127.0.0.1:{self.server.server_port}/api/mcp"
            )
        self.assertEqual(attempted_connections, 1)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} RENDERED_BROKER")
    unittest.main(argv=[sys.argv[0]], verbosity=2)
