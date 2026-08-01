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

    handler_body = handlers[0].body
    valid_handler = (
        len(handler_body) == 2
        and isinstance(handler_body[0], ast.Expr)
        and isinstance(handler_body[0].value, ast.Call)
        and isinstance(handler_body[0].value.func, ast.Attribute)
        and isinstance(handler_body[0].value.func.value, ast.Name)
        and handler_body[0].value.func.value.id == "self"
        and handler_body[0].value.func.attr == "stop_monitoring"
        and not handler_body[0].value.args
        and not handler_body[0].value.keywords
        and isinstance(handler_body[1], ast.Raise)
        and isinstance(handler_body[1].exc, ast.Call)
        and isinstance(handler_body[1].exc.func, ast.Name)
        and handler_body[1].exc.func.id == "SystemExit"
        and len(handler_body[1].exc.args) == 1
        and isinstance(handler_body[1].exc.args[0], ast.Constant)
        and handler_body[1].exc.args[0].value == 0
        and not handler_body[1].exc.keywords
    )
    runtime_blocks = [node for node in tree.body if isinstance(node, ast.Try)]
    guarded_cleanup = [
        block
        for block in runtime_blocks
        if len(block.finalbody) == 1
        and isinstance(block.finalbody[0], ast.If)
        and isinstance(block.finalbody[0].test, ast.Attribute)
        and isinstance(block.finalbody[0].test.value, ast.Name)
        and block.finalbody[0].test.value.id == "manager"
        and block.finalbody[0].test.attr == "monitoring"
        and len(block.finalbody[0].body) == 1
        and isinstance(block.finalbody[0].body[0], ast.Expr)
        and isinstance(block.finalbody[0].body[0].value, ast.Call)
        and isinstance(block.finalbody[0].body[0].value.func, ast.Attribute)
        and isinstance(block.finalbody[0].body[0].value.func.value, ast.Name)
        and block.finalbody[0].body[0].value.func.value.id == "manager"
        and block.finalbody[0].body[0].value.func.attr == "stop_monitoring"
        and not block.finalbody[0].body[0].value.args
        and not block.finalbody[0].body[0].value.keywords
        and not block.finalbody[0].orelse
    ]
    if not valid_handler or len(guarded_cleanup) != 1 or re.search(r"\batexit\b", source):
        raise UnsupportedSourceError("unsupported SIGTERM cleanup structure")


def _replace_in_handler(source: str, pattern: str, replacement: str, label: str) -> str:
    tree = ast.parse(source)
    manager = next(
        (node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "TaskManager"),
        None,
    )
    if manager is None:
        raise UnsupportedSourceError("expected exactly one TaskManager class")
    handler = next(
        (node for node in manager.body if isinstance(node, ast.FunctionDef) and node.name == "handle_signal"),
        None,
    )
    if handler is None or handler.end_lineno is None:
        raise UnsupportedSourceError("expected exactly one handle_signal method")
    lines = source.splitlines(keepends=True)
    handler_source = "".join(lines[handler.lineno - 1 : handler.end_lineno])
    lines[handler.lineno - 1 : handler.end_lineno] = [
        _replace_once(
            handler_source,
            pattern,
            replacement,
            label,
        )
    ]
    return "".join(lines)


def _replace_in_task_manager_method(
    source: str, method_name: str, pattern: str, replacement: str, label: str
) -> str:
    tree = ast.parse(source)
    manager = next(
        (node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "TaskManager"),
        None,
    )
    if manager is None:
        raise UnsupportedSourceError("expected exactly one TaskManager class")
    method = next(
        (
            node
            for node in manager.body
            if isinstance(node, ast.FunctionDef) and node.name == method_name
        ),
        None,
    )
    if method is None:
        return source
    if method.end_lineno is None:
        raise UnsupportedSourceError(f"expected exactly one TaskManager.{method_name} method")
    lines = source.splitlines(keepends=True)
    method_source = "".join(lines[method.lineno - 1 : method.end_lineno])
    lines[method.lineno - 1 : method.end_lineno] = [
        _replace_once(method_source, pattern, replacement, label)
    ]
    return "".join(lines)


def _is_manager_stop_monitoring(node: ast.AST) -> bool:
    return (
        isinstance(node, ast.Expr)
        and isinstance(node.value, ast.Call)
        and isinstance(node.value.func, ast.Attribute)
        and isinstance(node.value.func.value, ast.Name)
        and node.value.func.value.id == "manager"
        and node.value.func.attr == "stop_monitoring"
        and not node.value.args
        and not node.value.keywords
    )


def _is_guarded_manager_stop_monitoring(node: ast.AST) -> bool:
    return (
        isinstance(node, ast.If)
        and isinstance(node.test, ast.Attribute)
        and isinstance(node.test.value, ast.Name)
        and node.test.value.id == "manager"
        and node.test.attr == "monitoring"
        and len(node.body) == 1
        and _is_manager_stop_monitoring(node.body[0])
        and not node.orelse
    )


def _replace_runtime_final_cleanup(source: str) -> str:
    tree = ast.parse(source)
    blocks = [node for node in tree.body if isinstance(node, ast.Try) and node.end_lineno is not None]
    if len(blocks) != 1:
        raise UnsupportedSourceError("expected exactly one top-level runtime block")
    block = blocks[0]
    if len(block.finalbody) != 1:
        return source
    cleanup = block.finalbody[0]
    if _is_guarded_manager_stop_monitoring(cleanup):
        return source
    if not _is_manager_stop_monitoring(cleanup) or cleanup.end_lineno is None:
        return source
    lines = source.splitlines(keepends=True)
    cleanup_source = "".join(lines[cleanup.lineno - 1 : cleanup.end_lineno])
    match = re.fullmatch(r"([ \t]*)manager\.stop_monitoring\(\)[ \t]*\r?\n?", cleanup_source)
    if match is None:
        raise UnsupportedSourceError("unsupported top-level final cleanup")
    indent = match.group(1)
    lines[cleanup.lineno - 1 : cleanup.end_lineno] = [
        f"{indent}if manager.monitoring:\n{indent}    manager.stop_monitoring()\n"
    ]
    return "".join(lines)


def render(source: str) -> str:
    """Build and validate a candidate before any destination write."""
    rendered = _replace_in_task_manager_method(
        source,
        "__init__",
        r"^[ \t]*atexit\.register\(self\.(?:handle_signal|stop_monitoring)\)[ \t]*\r?\n",
        "",
        "atexit registration in TaskManager.__init__",
    )
    if not re.search(r"\batexit\.", rendered):
        rendered = _replace_once(
            rendered,
            r"^import atexit[ \t]*\r?\n",
            "",
            "atexit import",
        )
    rendered = _replace_in_handler(
        rendered,
        r"^([ \t]*)self\.stop_all_tasks\(\)[ \t]*$",
        r"\1self.stop_monitoring()\n\1raise SystemExit(0)",
        "obsolete signal cleanup in handle_signal",
    )
    rendered = _replace_runtime_final_cleanup(rendered)
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
        destination_metadata = _regular_file(destination, "destination")
        if (
            source_metadata.st_dev == destination_metadata.st_dev
            and source_metadata.st_ino == destination_metadata.st_ino
        ):
            raise UnsupportedSourceError("source and destination must not resolve to the same file")
    if not destination.parent.is_dir():
        raise UnsupportedSourceError(f"destination parent is not a directory: {destination.parent}")

    candidate = render(source.read_text(encoding="utf-8"))
    desired_mode = stat.S_IMODE(source_metadata.st_mode)
    if (
        destination.exists()
        and destination.read_text(encoding="utf-8") == candidate
        and stat.S_IMODE(destination_metadata.st_mode) == desired_mode
    ):
        return False
    if check:
        return True

    descriptor, temporary = tempfile.mkstemp(dir=destination.parent, prefix=f".{destination.name}.")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(candidate)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, desired_mode)
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
