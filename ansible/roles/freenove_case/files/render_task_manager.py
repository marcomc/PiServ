#!/usr/bin/env python3
"""Render a validated Freenove task manager with safe SIGTERM cleanup."""

from __future__ import annotations

import argparse
import ast
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


class UnsupportedSourceError(RuntimeError):
    """The upstream source does not match a supported state."""


def _replace_once(source: str, pattern: str, replacement: str, label: str) -> str:
    rendered, count = re.subn(pattern, replacement, source, flags=re.MULTILINE)
    if count > 1:
        raise UnsupportedSourceError(f"multiple {label} matches")
    return rendered


def _validate_candidate(source: str) -> None:
    tree = ast.parse(source)
    managers = [
        node
        for node in tree.body
        if isinstance(node, ast.ClassDef) and node.name == "TaskManager"
    ]
    if len(managers) != 1:
        raise UnsupportedSourceError("expected exactly one TaskManager class")
    handlers = [
        node
        for node in managers[0].body
        if isinstance(node, ast.FunctionDef) and node.name == "handle_signal"
    ]
    if len(handlers) != 1:
        raise UnsupportedSourceError("expected exactly one handle_signal method")

    lines = source.splitlines()
    handler = "\n".join(lines[handlers[0].lineno - 1 : handlers[0].end_lineno])
    valid_handler = (
        len(re.findall(r"(?m)^[ \t]*self\.stop_monitoring\(\)[ \t]*$", handler)) == 1
        and len(re.findall(r"(?m)^[ \t]*raise SystemExit\(0\)[ \t]*$", handler)) == 1
        and "self.stop_all_tasks()" not in handler
    )
    guarded_cleanup = re.findall(
        r"(?m)^[ \t]*finally:[ \t]*\r?\n"
        r"[ \t]+if manager\.monitoring:[ \t]*\r?\n"
        r"[ \t]+manager\.stop_monitoring\(\)[ \t]*$",
        source,
    )
    if not valid_handler or len(guarded_cleanup) != 1 or re.search(r"\batexit\b", source):
        raise UnsupportedSourceError("unsupported SIGTERM cleanup structure")


def render(source: str) -> str:
    """Build and validate a candidate before any destination write."""
    rendered = _replace_once(
        source,
        r"^[ \t]*atexit\.register\(self\.(?:handle_signal|stop_monitoring)\)[ \t]*\r?\n",
        "",
        "atexit registration",
    )
    rendered = _replace_once(
        rendered,
        r"^import atexit[ \t]*\r?\n",
        "",
        "atexit import",
    )
    rendered = _replace_once(
        rendered,
        r"^([ \t]*)self\.stop_all_tasks\(\)[ \t]*$",
        r"\1self.stop_monitoring()\n\1raise SystemExit(0)",
        "obsolete signal cleanup",
    )
    rendered = _replace_once(
        rendered,
        r"^([ \t]*)finally:[ \t]*\r?\n([ \t]+)manager\.stop_monitoring\(\)[ \t]*$",
        r"\1finally:\n\2if manager.monitoring:\n\2    manager.stop_monitoring()",
        "unguarded final cleanup",
    )
    _validate_candidate(rendered)
    return rendered


def _regular_file(path: Path, label: str) -> os.stat_result:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise UnsupportedSourceError(f"{label} does not exist: {path}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise UnsupportedSourceError(f"{label} must be a non-symlink regular file: {path}")
    return metadata


def write_candidate(source: Path, destination: Path, check: bool) -> bool:
    if source == destination:
        raise UnsupportedSourceError("source and destination paths must differ")
    source_metadata = _regular_file(source, "source")
    if destination.exists() or destination.is_symlink():
        _regular_file(destination, "destination")
    if not destination.parent.is_dir():
        raise UnsupportedSourceError(f"destination parent is not a directory: {destination.parent}")

    candidate = render(source.read_text(encoding="utf-8"))
    if destination.exists() and destination.read_text(encoding="utf-8") == candidate:
        return False
    if check:
        return True

    descriptor, temporary = tempfile.mkstemp(dir=destination.parent, prefix=f".{destination.name}.")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(candidate)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, stat.S_IMODE(source_metadata.st_mode))
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    try:
        changed = write_candidate(arguments.source, arguments.destination, arguments.check)
    except (OSError, UnicodeError, SyntaxError, UnsupportedSourceError) as error:
        print(f"render_task_manager: {error}", file=sys.stderr)
        return 1
    print("changed" if changed else "unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
