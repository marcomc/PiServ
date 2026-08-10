#!/usr/bin/env python3
"""Validate a source-scoped Hermes session export for one entity."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections.abc import Iterable
from pathlib import Path
from typing import Any

ENTITY_ID_PATTERN = re.compile(r"\b[a-z0-9_]+\.[a-z0-9_]+\b")
ALLOWED_HERMES_MCP_TOOLS = {
    "mcp__home_assistant_assist__GetLiveContext",
    "mcp__home_assistant_assist__HassTurnOn",
    "mcp__home_assistant_assist__HassTurnOff",
}
HERMES_MUTATION_TOOLS = {
    "mcp__home_assistant_assist__HassTurnOn",
    "mcp__home_assistant_assist__HassTurnOff",
}


class AuditError(RuntimeError):
    """Raised when a Hermes session export is incomplete or out of scope."""


def entity_ids(value: Any) -> set[str]:
    """Return entity IDs found anywhere in a JSON-compatible value."""
    if isinstance(value, str):
        return set(ENTITY_ID_PATTERN.findall(value))
    if isinstance(value, dict):
        return set().union(*(entity_ids(item) for item in value.values()))
    if isinstance(value, list):
        return set().union(*(entity_ids(item) for item in value))
    return set()


def _object(value: Any, context: str) -> dict[str, Any]:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError as error:
            raise AuditError(f"{context} contains invalid JSON") from error
    if not isinstance(value, dict):
        raise AuditError(f"{context} must be an object")
    return value


def validate_tool_calls(
    tool_calls: Iterable[Any], entity_id: str, label: str
) -> dict[str, Any]:
    """Validate audited tool calls against the shared smart-home allowlist."""
    audited_tools: list[str] = []
    mutation_tools: list[str] = []
    for call_value in tool_calls:
        call = _object(call_value, f"Hermes task audit record for {label}")
        function_name = call.get("name")
        arguments = _object(
            call.get("arguments", {}), f"Hermes tool arguments for {label}"
        )
        if function_name == "tool_describe":
            described_name = arguments.get("name")
            if described_name not in ALLOWED_HERMES_MCP_TOOLS:
                raise AuditError(
                    f"Hermes described a non-allowlisted tool for {label}: "
                    f"{described_name!r}"
                )
            continue
        if function_name != "tool_call":
            raise AuditError(
                f"Hermes used an unexpected tool-call record for {label}: "
                f"{function_name!r}"
            )

        called_name = arguments.get("name")
        called_arguments = _object(
            arguments.get("arguments", {}),
            f"Hermes called-tool arguments for {label}",
        )
        if called_name not in ALLOWED_HERMES_MCP_TOOLS:
            raise AuditError(
                f"Hermes used a non-allowlisted tool for {label}: {called_name!r}"
            )
        audited_tools.append(called_name)
        if called_name in HERMES_MUTATION_TOOLS:
            if entity_ids(called_arguments) != {entity_id}:
                raise AuditError(
                    f"Hermes addressed an entity outside the allowlist for {label}"
                )
            mutation_tools.append(called_name)

    if not mutation_tools:
        raise AuditError(f"Hermes task audit recorded no mutation for {label}")
    return {"tool_names": audited_tools, "entity_ids": [entity_id]}


def validate_session_export(
    records: Iterable[Any], source: str, entity_id: str, label: str
) -> dict[str, Any]:
    """Validate exact source provenance and tool calls from exported sessions."""
    records = list(records)
    if not source or not records:
        raise AuditError(f"Hermes task audit was not captured for {label}")

    tool_calls: list[Any] = []
    for record_value in records:
        record = _object(record_value, f"Hermes session record for {label}")
        if record.get("source") != source:
            raise AuditError(f"Hermes task audit source mismatch for {label}")
        messages = record.get("messages")
        if not isinstance(messages, list):
            raise AuditError(f"Hermes task audit has invalid messages for {label}")
        for message in messages:
            message = _object(message, f"Hermes audit message for {label}")
            calls = message.get("tool_calls", [])
            if not isinstance(calls, list):
                raise AuditError(f"Hermes task audit has invalid calls for {label}")
            for call in calls:
                call = _object(call, f"Hermes task audit call for {label}")
                function = _object(
                    call.get("function"),
                    f"Hermes task audit function for {label}",
                )
                tool_calls.append(function)

    summary = validate_tool_calls(tool_calls, entity_id, label)
    summary["source"] = source
    summary["session_records"] = len(records)
    return summary


def load_jsonl(path: Path) -> list[Any]:
    """Load a non-empty JSONL export."""
    records = []
    for line_number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as error:
            raise AuditError(f"invalid JSONL at line {line_number}") from error
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export", required=True, type=Path)
    parser.add_argument("--source", required=True)
    parser.add_argument("--entity", required=True)
    parser.add_argument("--label", required=True)
    args = parser.parse_args()
    try:
        summary = validate_session_export(
            load_jsonl(args.export), args.source, args.entity, args.label
        )
    except (AuditError, OSError) as error:
        print(f"Hermes audit rejected: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
