#!/usr/bin/env python3
"""Exercise the rendered Hermes delegation MCP adapter without MCP packages."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import textwrap
import time
import types
import unittest
from pathlib import Path

ADAPTER_PATH = ""


class ToolError(Exception):
    """Test replacement for the MCP SDK ToolError."""


class FastMCP:
    """Minimal decorator-compatible FastMCP replacement."""

    def __init__(self, *args, **kwargs) -> None:
        self.args = args
        self.kwargs = kwargs

    def tool(self):
        return lambda function: function

    def run(self, **kwargs) -> None:
        raise AssertionError(f"unexpected server run: {kwargs}")


def load_adapter(adapter_path: Path):
    """Import a rendered adapter with only its MCP imports stubbed."""
    mcp_module = types.ModuleType("mcp")
    server_module = types.ModuleType("mcp.server")
    fastmcp_module = types.ModuleType("mcp.server.fastmcp")
    exceptions_module = types.ModuleType("mcp.server.fastmcp.exceptions")
    fastmcp_module.FastMCP = FastMCP
    exceptions_module.ToolError = ToolError
    sys.modules.update(
        {
            "mcp": mcp_module,
            "mcp.server": server_module,
            "mcp.server.fastmcp": fastmcp_module,
            "mcp.server.fastmcp.exceptions": exceptions_module,
        }
    )
    spec = importlib.util.spec_from_file_location(
        "rendered_hermes_delegation_adapter", adapter_path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load adapter: {adapter_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AdapterTests(unittest.TestCase):
    """Verify invocation safety and every bounded failure mode."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory()
        temporary_path = Path(cls.temporary_directory.name)
        cls.side_effect_path = temporary_path / "shell-interpolation-must-not-run"
        cls.fake_hermes = temporary_path / "fake-hermes"
        cls.fake_hermes.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import json
                import pathlib
                import subprocess
                import sys
                import time

                prompt = sys.argv[sys.argv.index("--query") + 1]
                if prompt == "fail":
                    print("credential=must-not-be-returned", file=sys.stderr)
                    raise SystemExit(7)
                if prompt == "sleep-with-child":
                    marker = pathlib.Path(sys.argv[0]).with_name(
                        "timed-out-child-marker"
                    )
                    subprocess.Popen(
                        [
                            sys.executable,
                            "-c",
                            (
                                "import pathlib, sys, time; time.sleep(1); "
                                "pathlib.Path(sys.argv[1]).touch()"
                            ),
                            str(marker),
                        ]
                    )
                    time.sleep(5)
                if prompt == "flood":
                    print("x" * 100000)
                    raise SystemExit(0)
                print(json.dumps(sys.argv[1:]))
                """
            ),
            encoding="utf-8",
        )
        cls.fake_hermes.chmod(0o755)
        cls.adapter = load_adapter(Path(ADAPTER_PATH))
        cls.adapter.HERMES_BINARY = str(cls.fake_hermes)
        cls.adapter.MAX_PROMPT_BYTES = 4096
        cls.adapter.MAX_OUTPUT_BYTES = 1024
        cls.adapter.TIMEOUT_SECONDS = 2.0
        cls.adapter.TERMINATE_GRACE_SECONDS = 0.1
        cls.adapter.POLL_SECONDS = 0.01

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_prompt_is_one_literal_argv_value(self) -> None:
        prompt = f"literal $(touch {self.side_effect_path}) ; $HOME"
        arguments = json.loads(self.adapter.delegate_task(prompt))
        self.assertEqual(
            self.adapter.TOOLSETS,
            "delegation,file,memory,session_search,skills,terminal,todo,"
            "home-assistant-assist",
        )
        self.assertEqual(
            arguments,
            [
                "chat",
                "--query",
                prompt,
                "--quiet",
                "--yolo",
                "--source",
                "tool",
                "--max-turns",
                str(self.adapter.MAX_TURNS),
                "--toolsets",
                self.adapter.TOOLSETS,
            ],
        )
        self.assertFalse(self.side_effect_path.exists())

    def test_empty_prompt_is_rejected(self) -> None:
        with self.assertRaisesRegex(ToolError, "non-empty"):
            self.adapter.delegate_task("  ")

    def test_oversized_prompt_is_rejected(self) -> None:
        with self.assertRaisesRegex(ToolError, "byte limit"):
            self.adapter.delegate_task("x" * 4097)

    def test_multibyte_oversized_prompt_is_rejected(self) -> None:
        with self.assertRaisesRegex(ToolError, "byte limit"):
            self.adapter.delegate_task("€" * 1366)

    def test_nonzero_exit_is_generic_and_redacted(self) -> None:
        with self.assertRaises(ToolError) as raised:
            self.adapter.delegate_task("fail")
        self.assertIn("exit status 7", str(raised.exception))
        self.assertNotIn("credential", str(raised.exception))

    def test_timeout_terminates_the_process_group(self) -> None:
        original_timeout = self.adapter.TIMEOUT_SECONDS
        self.adapter.TIMEOUT_SECONDS = 0.2
        try:
            with self.assertRaisesRegex(ToolError, "second limit"):
                self.adapter.delegate_task("sleep-with-child")
            child_marker = self.fake_hermes.with_name("timed-out-child-marker")
            time.sleep(1.1)
            self.assertFalse(child_marker.exists())
        finally:
            self.adapter.TIMEOUT_SECONDS = original_timeout

    def test_output_limit_terminates_the_process_group(self) -> None:
        with self.assertRaisesRegex(ToolError, "output limit"):
            self.adapter.delegate_task("flood")

    def test_concurrent_turn_is_rejected(self) -> None:
        self.adapter._delegation_lock.acquire()
        try:
            with self.assertRaisesRegex(ToolError, "already processing"):
                self.adapter.delegate_task("busy")
        finally:
            self.adapter._delegation_lock.release()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} RENDERED_ADAPTER")
    ADAPTER_PATH = sys.argv[1]
    unittest.main(argv=[sys.argv[0]], verbosity=2)
