"""Verify Hermes -> Home Assistant -> HomeKit propagation from the Mac."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

DEFAULT_CONFIG = Path(__file__).with_name("hermes-home-apple-home.local.json")
DEFAULT_REPORT_ROOT = Path("artifacts/hermes-home-apple-home")
DEFAULT_TIMEOUT = 30.0
DEFAULT_POLL_INTERVAL = 2.0
SSH_OPTIONS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]


class VerificationError(RuntimeError):
    """Raised when a release acceptance precondition or assertion fails."""


def utc_now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def run_command(command: list[str], timeout: float) -> dict[str, Any]:
    started = time.monotonic()
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return {
            "command": command,
            "duration_seconds": round(time.monotonic() - started, 3),
            "exit_code": None,
            "stdout": "",
            "stderr": str(error),
            "timed_out": isinstance(error, subprocess.TimeoutExpired),
        }
    return {
        "command": command,
        "duration_seconds": round(time.monotonic() - started, 3),
        "exit_code": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "timed_out": False,
    }


def redact(value: str) -> str:
    value = re.sub(
        r"Bearer\s+\S+", "Bearer [REDACTED]", value, flags=re.IGNORECASE
    )
    return re.sub(r"HASS_MCP_TOKEN=\S+", "HASS_MCP_TOKEN=[REDACTED]", value)


def compact_result(result: dict[str, Any]) -> dict[str, Any]:
    stdout = result.get("stdout", "")
    stderr = result.get("stderr", "")
    if stdout:
        result["stdout_sha256"] = hashlib.sha256(stdout.encode()).hexdigest()
        result["stdout_bytes"] = len(stdout.encode())
        result["stdout"] = ""
    if stderr:
        result["stderr"] = redact(stderr)
    return result


def checked_json(result: dict[str, Any], description: str) -> Any:
    if result["exit_code"] != 0:
        raise VerificationError(
            f"{description} failed: {redact(result['stderr']).strip()}"
        )
    try:
        return json.loads(result["stdout"])
    except json.JSONDecodeError as error:
        raise VerificationError(f"{description} returned invalid JSON") from error


def require_string(mapping: dict[str, Any], key: str, context: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise VerificationError(f"{context} requires a non-empty '{key}'")
    return value


def validate_config(config: dict[str, Any]) -> None:
    ssh_target = require_string(config, "ssh_target", "configuration")
    if any(character.isspace() for character in ssh_target):
        raise VerificationError("ssh_target must be a single SSH target")
    require_string(config, "home_assistant_api_url", "configuration")
    entities = config.get("entities")
    if not isinstance(entities, list) or not entities:
        raise VerificationError("configuration requires at least one entity")

    for index, entity in enumerate(entities):
        context = f"entities[{index}]"
        if not isinstance(entity, dict):
            raise VerificationError(f"{context} must be an object")
        for key in (
            "label",
            "home_assistant_entity_id",
            "homeclaw_accessory",
            "homeclaw_characteristic",
            "risk",
        ):
            require_string(entity, key, context)
        if entity["risk"] != "non-critical":
            raise VerificationError(
                f"{context} must explicitly declare risk=non-critical"
            )
        if entity["homeclaw_characteristic"] != "power":
            raise VerificationError(
                f"{context} currently supports only the reversible power check"
            )

    scenes = config.get("scenes", [])
    if not isinstance(scenes, list) or any(not isinstance(scene, str) for scene in scenes):
        raise VerificationError("scenes must be a list of names")


def homeclaw_json(subcommand: list[str], timeout: float) -> tuple[Any, dict[str, Any]]:
    result = run_command(["homeclaw-cli", *subcommand, "--json"], timeout)
    payload = checked_json(result, f"homeclaw-cli {' '.join(subcommand)}")
    return payload, compact_result(result)


def homeclaw_state(accessory: str, characteristic: str, timeout: float) -> dict[str, Any]:
    payload, _ = homeclaw_json(["get", accessory], timeout)
    for service in payload.get("services", []):
        for item in service.get("characteristics", []):
            if item.get("name") == characteristic:
                return {
                    "accessory": payload.get("name", accessory),
                    "reachable": payload.get("reachable"),
                    "characteristic": characteristic,
                    "value": item.get("value"),
                }
    raise VerificationError(
        f"HomeClaw accessory {accessory!r} has no {characteristic!r} characteristic"
    )


def normalize_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.lower() in {"true", "false"}:
        return value.lower() == "true"
    raise VerificationError(f"expected a boolean power value, got {value!r}")


def remote_home_assistant_state(
    config: dict[str, Any], entity_id: str, timeout: float
) -> tuple[dict[str, Any], dict[str, Any]]:
    api_url = require_string(config, "home_assistant_api_url", "configuration").rstrip("/")
    token_file = config.get(
        "home_assistant_token_env_file",
        "/var/lib/hermes-agent/home-assistant-mcp.env",
    )
    remote_script = "\n".join(
        [
            "set -eu",
            "set -a",
            f". {shlex.quote(token_file)}",
            "set +a",
            'curl_config="$(mktemp)"',
            'trap \'rm -f -- "$curl_config"\' EXIT',
            'chmod 0600 "$curl_config"',
            'printf \'header = "Authorization: Bearer %s"\\n\' "$HASS_MCP_TOKEN" >"$curl_config"',
            (
                "curl --config \"$curl_config\" --fail --silent --show-error "
                f"--max-time 10 {shlex.quote(api_url + '/states/' + entity_id)}"
            ),
        ]
    )
    remote_command = shlex.join(
        [
            "sudo",
            "-u",
            "hermes-agent",
            "-H",
            "sh",
            "-c",
            remote_script,
        ]
    )
    command = ["ssh", *SSH_OPTIONS, config["ssh_target"], remote_command]
    result = run_command(command, timeout)
    payload = checked_json(result, f"Home Assistant state for {entity_id}")
    return payload, compact_result(result)


def invoke_hermes(
    config: dict[str, Any], prompt: str, timeout: float, max_turns: int
) -> dict[str, Any]:
    token_file = config.get(
        "home_assistant_token_env_file",
        "/var/lib/hermes-agent/home-assistant-mcp.env",
    )
    hermes_command = shlex.join(
        [
            "env",
            f"HERMES_HOME={config.get('hermes_home', '/var/lib/hermes-agent')}",
            f"CODEX_HOME={config.get('codex_home', '/var/lib/hermes-agent/codex')}",
            config.get("hermes_binary", "/usr/local/bin/hermes"),
            "chat",
            "--query",
            prompt,
            "--quiet",
            "--toolsets",
            "home-assistant-assist",
            "--max-turns",
            str(max_turns),
        ]
    )
    remote_script = "\n".join(
        [
            "set -eu",
            "set -a",
            f". {shlex.quote(token_file)}",
            "set +a",
            "cd /var/lib/hermes-agent/workspace",
            f"exec {hermes_command}",
        ]
    )
    remote_command = shlex.join(
        ["sudo", "-u", "hermes-agent", "-H", "bash", "-c", remote_script]
    )
    result = run_command(
        ["ssh", *SSH_OPTIONS, config["ssh_target"], remote_command], timeout
    )
    result["stdout"] = redact(result["stdout"])
    result["stderr"] = redact(result["stderr"])
    return compact_result(result)


def poll(
    check: Any, timeout: float, interval: float, description: str
) -> Any:
    deadline = time.monotonic() + timeout
    last_error = "not observed"
    while time.monotonic() <= deadline:
        try:
            value = check()
            if value:
                return value
            last_error = "observed state did not match"
        except VerificationError as error:
            last_error = str(error)
        time.sleep(interval)
    raise VerificationError(f"timeout waiting for {description}: {last_error}")


def write_reports(report: dict[str, Any], report_dir: Path) -> None:
    report_dir.mkdir(parents=True, exist_ok=True)
    json_path = report_dir / "report.json"
    text_path = report_dir / "report.txt"
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    summary = [
        f"status: {report['status']}",
        f"started: {report['started_at']}",
        f"finished: {report.get('finished_at', 'in progress')}",
        f"target: {report.get('target_label', 'none')}",
        f"report: {json_path}",
    ]
    if report.get("failure"):
        summary.append(f"failure: {report['failure']}")
    text_path.write_text("\n".join(summary) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path(os.environ.get("PISERV_HERMES_HOME_APPLE_CONFIG", DEFAULT_CONFIG)))
    parser.add_argument("--report-dir", type=Path)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    parser.add_argument("--poll-interval", type=float, default=DEFAULT_POLL_INTERVAL)
    parser.add_argument("--max-turns", type=int, default=20)
    parser.add_argument("--dry-run", action="store_true", help="Run preflight without changing Home Assistant state")
    return parser.parse_args()


def verify_entity(
    config: dict[str, Any],
    entity: dict[str, Any],
    args: argparse.Namespace,
    report: dict[str, Any],
) -> None:
    target: dict[str, Any] = {
        "label": entity["label"],
        "home_assistant_entity_id": entity["home_assistant_entity_id"],
        "homeclaw_accessory": entity["homeclaw_accessory"],
        "characteristic": entity["homeclaw_characteristic"],
    }
    report["targets"].append(target)
    before_homeclaw = homeclaw_state(
        entity["homeclaw_accessory"], entity["homeclaw_characteristic"], args.timeout
    )
    before_ha, result = remote_home_assistant_state(
        config, entity["home_assistant_entity_id"], args.timeout
    )
    report["commands"].append(result)
    before_power = normalize_bool(before_homeclaw["value"])
    desired_power = not before_power
    target["before"] = {
        "homeclaw": before_homeclaw,
        "home_assistant_state": before_ha.get("state"),
    }
    target["desired_power"] = desired_power
    if normalize_bool(before_ha.get("state") == "on") != before_power:
        raise VerificationError(
            f"Home Assistant and HomeClaw initial states differ for {entity['label']}"
        )
    if args.dry_run:
        return

    action_prompt = (
        "Hermes Home/Apple acceptance test v1. You have explicit full autonomy "
        "for this named, non-critical test activity only. Use only the "
        "home-assistant-assist MCP server. Before changing anything, preserve "
        "the current state of the named test entity in your task audit. Do not "
        "touch any other entity, automation, scene, configuration, lock, alarm, "
        "gate, or security device. Set Home Assistant entity "
        f"{entity['home_assistant_entity_id']} to "
        f"{'on' if desired_power else 'off'}, then read it back and report the "
        "result. This entity is explicitly classified as non-critical."
    )
    original_power = "true" if before_power else "false"
    mutation_attempted = False

    def restore() -> None:
        if not mutation_attempted or target.get("restored") is not None:
            return
        restore_prompt = (
            "Hermes Home/Apple acceptance test cleanup. You have explicit full "
            "autonomy for this named, non-critical cleanup activity only. Restore "
            "only the test entity and then verify it. Use only "
            "Home Assistant MCP. Restore entity "
            f"{entity['home_assistant_entity_id']} to "
            f"{'on' if before_power else 'off'} and touch nothing else."
        )
        target["hermes_restore"] = invoke_hermes(
            config, restore_prompt, args.timeout * 2, args.max_turns
        )
        if target["hermes_restore"]["exit_code"] != 0:
            raise VerificationError(f"Hermes cleanup failed for {entity['label']}")
        target["restored"] = poll(
            lambda: expected_restore(config, entity, original_power, report, args.timeout),
            args.timeout,
            args.poll_interval,
            f"test entity restoration for {entity['label']}",
        )

    try:
        mutation_attempted = True
        target["hermes_action"] = invoke_hermes(
            config, action_prompt, args.timeout * 2, args.max_turns
        )
        if target["hermes_action"]["exit_code"] != 0:
            raise VerificationError(f"Hermes action failed for {entity['label']}")

        def expected_state() -> dict[str, Any] | None:
            homeclaw = homeclaw_state(
                entity["homeclaw_accessory"], entity["homeclaw_characteristic"], args.timeout
            )
            ha, result = remote_home_assistant_state(
                config, entity["home_assistant_entity_id"], args.timeout
            )
            report["commands"].append(result)
            if normalize_bool(ha.get("state") == "on") != desired_power:
                return None
            if normalize_bool(homeclaw["value"]) != desired_power:
                return None
            return {"homeclaw": homeclaw, "home_assistant_state": ha.get("state")}

        target["after"] = poll(
            expected_state,
            args.timeout,
            args.poll_interval,
            f"Home Assistant and Apple Home to converge for {entity['label']}",
        )
    finally:
        restore()


def main() -> int:
    args = parse_args()
    if args.timeout <= 0 or args.poll_interval <= 0 or args.max_turns <= 0:
        raise VerificationError("timeout, poll interval, and max turns must be positive")
    report_dir = args.report_dir or DEFAULT_REPORT_ROOT / datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    report: dict[str, Any] = {
        "schema": 1,
        "status": "failed",
        "started_at": utc_now(),
        "config": str(args.config),
        "commands": [],
        "targets": [],
        "dry_run": args.dry_run,
    }
    try:
        if not args.config.is_file():
            raise VerificationError(f"configuration file not found: {args.config}")
        config_bytes = args.config.read_bytes()
        config = json.loads(config_bytes)
        if not isinstance(config, dict):
            raise VerificationError("configuration root must be an object")
        validate_config(config)
        report["config_sha256"] = hashlib.sha256(config_bytes).hexdigest()

        status, result = homeclaw_json(["status"], args.timeout)
        report["commands"].append(result)
        if not status.get("ready"):
            raise VerificationError("HomeClaw is not ready")

        scenes, result = homeclaw_json(["scenes"], args.timeout)
        report["commands"].append(result)
        for scene in config.get("scenes", []):
            if not any(item.get("name") == scene for item in scenes):
                raise VerificationError(f"configured HomeKit scene not found: {scene}")

        for entity in config["entities"]:
            verify_entity(config, entity, args, report)
        report["status"] = "passed"
    except (OSError, ValueError, VerificationError, json.JSONDecodeError) as error:
        report["failure"] = str(error)
    finally:
        report["finished_at"] = utc_now()
        write_reports(report, report_dir)

    print(json.dumps({"status": report["status"], "report_dir": str(report_dir), "failure": report.get("failure")}, sort_keys=True))
    return 0 if report["status"] == "passed" else 1


def expected_restore(
    config: dict[str, Any],
    entity: dict[str, Any],
    original_power: str,
    report: dict[str, Any],
    timeout: float,
) -> dict[str, Any] | None:
    homeclaw = homeclaw_state(
        entity["homeclaw_accessory"], entity["homeclaw_characteristic"], timeout
    )
    ha, result = remote_home_assistant_state(
        config, entity["home_assistant_entity_id"], timeout
    )
    report["commands"].append(result)
    expected = original_power == "true"
    if normalize_bool(ha.get("state") == "on") != expected:
        return None
    if normalize_bool(homeclaw["value"]) != expected:
        return None
    return {"homeclaw": homeclaw, "home_assistant_state": ha.get("state")}


if __name__ == "__main__":
    try:
        sys.exit(main())
    except VerificationError as error:
        print(f"verification failed: {error}", file=sys.stderr)
        sys.exit(1)
