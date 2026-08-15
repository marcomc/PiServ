#!/usr/bin/env python3
"""Exercise a Hermes delegation MCP stdio command through JSON-RPC."""

from __future__ import annotations

import argparse
import json
import selectors
import subprocess
import sys
import time
from typing import Any


class ProtocolError(RuntimeError):
    """Raised when the MCP process violates the expected protocol contract."""


def write_message(process: subprocess.Popen[str], message: dict[str, Any]) -> None:
    """Send one newline-delimited MCP JSON-RPC message."""
    if process.stdin is None:
        raise ProtocolError("MCP stdin is unavailable")
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


def read_response(
    process: subprocess.Popen[str], request_id: int, timeout: float
) -> dict[str, Any]:
    """Read notifications until the response for request_id arrives."""
    if process.stdout is None:
        raise ProtocolError("MCP stdout is unavailable")
    deadline = time.monotonic() + timeout
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        while time.monotonic() < deadline:
            events = selector.select(deadline - time.monotonic())
            if not events:
                break
            line = process.stdout.readline()
            if not line:
                raise ProtocolError(
                    f"MCP process ended before response {request_id}; exit={process.poll()}"
                )
            try:
                message = json.loads(line)
            except json.JSONDecodeError as error:
                raise ProtocolError(
                    f"non-JSON MCP stdout: {line.rstrip()!r}"
                ) from error
            if message.get("id") == request_id:
                return message
    raise ProtocolError(f"timed out waiting for MCP response {request_id}")


def exercise(command: list[str], prompt: str, timeout: float) -> dict[str, Any]:
    """Initialize, discover delegate_task, call it, and return the result."""
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    try:
        write_message(
            process,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": {
                        "name": "piserv-hermes-delegation-test",
                        "version": "1",
                    },
                },
            },
        )
        initialize = read_response(process, 1, timeout)
        if "error" in initialize:
            raise ProtocolError(f"initialize failed: {initialize['error']}")
        write_message(
            process,
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
        )
        write_message(
            process,
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        )
        tools_response = read_response(process, 2, timeout)
        tools = tools_response.get("result", {}).get("tools", [])
        tool_names = [tool.get("name") for tool in tools]
        if tool_names != ["delegate_task"]:
            raise ProtocolError(f"unexpected MCP tools: {tool_names}")
        write_message(
            process,
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": "delegate_task", "arguments": {"prompt": prompt}},
            },
        )
        call_response = read_response(process, 3, timeout)
        if "error" in call_response:
            raise ProtocolError(f"delegate_task MCP error: {call_response['error']}")
        result = call_response.get("result", {})
        if result.get("isError"):
            raise ProtocolError(f"delegate_task tool error: {result.get('content')}")
        return result
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def main() -> int:
    """Parse the MCP command and print its successful call result as JSON."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--timeout", type=float, default=360.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("an MCP stdio command is required after --")
    result = exercise(command, args.prompt, args.timeout)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
