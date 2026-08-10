"""Verify Hermes -> Home Assistant -> HomeKit propagation from the Mac."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import ipaddress
import json
import math
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

DEFAULT_CONFIG = Path(__file__).with_name("hermes-home-apple-home.local.json")
DEFAULT_REPORT_ROOT = Path("artifacts/hermes-home-apple-home")
DEFAULT_TIMEOUT = 30.0
DEFAULT_POLL_INTERVAL = 2.0
MAX_TIMEOUT = 300.0
MAX_POLL_INTERVAL = 30.0
MAX_TURNS = 100
SSH_OPTIONS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
AUDIT_HELPER_PATH = Path(__file__).with_name("hermes_audit.py")
AUDIT_SPEC = importlib.util.spec_from_file_location("hermes_audit", AUDIT_HELPER_PATH)
if AUDIT_SPEC is None or AUDIT_SPEC.loader is None:
    raise RuntimeError(f"cannot load Hermes audit helper: {AUDIT_HELPER_PATH}")
HERMES_AUDIT = importlib.util.module_from_spec(AUDIT_SPEC)
AUDIT_SPEC.loader.exec_module(HERMES_AUDIT)
MANAGED_POLICY_PATH = "/etc/hermes-agent/policies/smart-home-AGENTS.md"
MANAGED_CONFIG_PATH = "/usr/local/lib/hermes-agent/.hermes-config.yaml"


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


def parse_ssh_target(target: str) -> tuple[str | None, str]:
    """Parse a strict OpenSSH destination without accepting CLI syntax."""
    if not target or target != target.strip() or any(
        character.isspace() for character in target
    ):
        raise VerificationError("ssh_target must be a single SSH target")
    if target.startswith("-") or target.count("@") > 1:
        raise VerificationError("ssh_target must use [user@]host syntax")

    user, separator, host = target.rpartition("@")
    if not separator:
        user, host = None, target
    elif not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", user):
        raise VerificationError("ssh_target has an invalid user")

    if host.startswith("["):
        if not host.endswith("]") or host.count("[") != 1 or host.count("]") != 1:
            raise VerificationError("ssh_target has an invalid bracketed IPv6 host")
        literal = host[1:-1]
        if "%" in literal:
            raise VerificationError("ssh_target IPv6 scope identifiers are not allowed")
        try:
            address = ipaddress.ip_address(literal)
        except ValueError as error:
            raise VerificationError(
                "ssh_target brackets may contain only an IPv6 address"
            ) from error
        if address.version != 6:
            raise VerificationError(
                "ssh_target brackets may contain only an IPv6 address"
            )
        return user, host

    if any(character in host for character in ":/[]"):
        raise VerificationError(
            "ssh_target must not contain a port, CIDR, or unbracketed IPv6 address"
        )
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        if re.fullmatch(r"[0-9.]+", host):
            raise VerificationError("ssh_target has an invalid IPv4 address")
        if len(host) > 253 or not re.fullmatch(
            r"(?=.{1,253}\.?$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*"
            r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.?",
            host,
        ):
            raise VerificationError("ssh_target has an invalid hostname")
    else:
        if address.version != 4:
            raise VerificationError("ssh_target IPv6 addresses must be bracketed")
    return user, host


def ssh_target(config: dict[str, Any]) -> str:
    configured_target = require_string(config, "ssh_target", "configuration")
    configured_user, _ = parse_ssh_target(configured_target)
    if "PISERV_IP" not in os.environ:
        return configured_target
    override = os.environ["PISERV_IP"]
    try:
        address = ipaddress.ip_address(override)
    except ValueError:
        raise VerificationError("PISERV_IP must be a single current DHCP lease")
    formatted_host = f"[{override}]" if address.version == 6 else override
    user = configured_user or "admin"
    return f"{user}@{formatted_host}"


def validate_config(config: dict[str, Any]) -> None:
    parse_ssh_target(require_string(config, "ssh_target", "configuration"))
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


def require_reachable(state: dict[str, Any], label: str) -> None:
    if state.get("reachable") is not True:
        raise VerificationError(f"HomeClaw accessory is not reachable for {label}")


def home_assistant_power_state(payload: dict[str, Any], label: str) -> bool:
    state = payload.get("state")
    if state not in {"on", "off"}:
        raise VerificationError(
            f"Home Assistant entity has unsupported state for {label}: {state!r}"
        )
    return state == "on"


def validate_hermes_audit(
    invocation: dict[str, Any], entity_id: str, label: str,
    expected_state: str | None = None,
) -> dict[str, Any]:
    try:
        if not invocation.get("audit_complete"):
            raise VerificationError(f"Hermes task audit was not captured for {label}")
        try:
            if "audit_records" in invocation:
                return HERMES_AUDIT.validate_session_export(
                    invocation["audit_records"], invocation.get("source", ""),
                    entity_id, label, expected_state,
                )
            return HERMES_AUDIT.validate_tool_calls(
                invocation.get("tool_calls", []), entity_id, label, expected_state
            )
        except HERMES_AUDIT.AuditError as error:
            raise VerificationError(str(error)) from error
    finally:
        invocation.pop("tool_calls", None)
        invocation.pop("audit_records", None)


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
    curl_script = "\n".join(
        [
            "set -eu",
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
            "systemd-run",
            "--quiet",
            "--wait",
            "--pipe",
            "--collect",
            "--service-type=exec",
            "--uid=hermes-agent",
            f"--property=EnvironmentFile={token_file}",
            "--property=NoNewPrivileges=yes",
            "--property=PrivateTmp=yes",
            "--property=ProtectSystem=strict",
            "--",
            "sh",
            "-c",
            curl_script,
        ]
    )
    command = ["ssh", *SSH_OPTIONS, ssh_target(config), remote_command]
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
    hermes_home = config.get("hermes_home", "/var/lib/hermes-agent")
    hermes_binary = config.get("hermes_binary", "/usr/local/bin/hermes")
    if not isinstance(hermes_home, str) or not hermes_home.strip():
        raise VerificationError("hermes_home must be a non-empty string")
    if not isinstance(hermes_binary, str) or not hermes_binary.strip():
        raise VerificationError("hermes_binary must be a non-empty string")
    source_tag = f"piserv-home-apple-{time.time_ns()}-{os.getpid()}"
    unit_suffix = hashlib.sha256(source_tag.encode()).hexdigest()[:16]
    action_unit = f"piserv-hermes-action-{unit_suffix}.service"
    export_unit = f"piserv-hermes-export-{unit_suffix}.service"
    associated_units = [action_unit, export_unit]
    hermes_command = shlex.join(
        [
            "env",
            f"HERMES_HOME={hermes_home}",
            f"CODEX_HOME={config.get('codex_home', '/var/lib/hermes-agent/codex')}",
            hermes_binary,
            "chat",
            "--query",
            prompt,
            "--quiet",
            "--toolsets",
            "home-assistant-assist",
            "--max-turns",
            str(max_turns),
            "--source",
            source_tag,
        ]
    )
    workspace = f"{hermes_home}/workspace"
    protected_command = shlex.join(
        [
            "sudo",
            "systemd-run",
            "--quiet",
            "--wait",
            "--pipe",
            "--collect",
            f"--unit={action_unit.removesuffix('.service')}",
            "--service-type=exec",
            "--uid=hermes-agent",
            f"--setenv=HOME={hermes_home}",
            "--property=RuntimeMaxSec=5min",
            "--property=NoNewPrivileges=yes",
            "--property=PrivateTmp=yes",
            "--property=ProtectSystem=strict",
            "--property=ProtectHome=yes",
            f"--property=ReadWritePaths={hermes_home}",
            f"--property=BindReadOnlyPaths={MANAGED_CONFIG_PATH}:{hermes_home}/config.yaml",
            f"--property=EnvironmentFile={token_file}",
            f"--property=BindReadOnlyPaths={MANAGED_POLICY_PATH}:{workspace}/AGENTS.md",
            "--property=RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6",
            f"--working-directory={workspace}",
            "--",
            "bash",
            "-c",
            hermes_command,
        ]
    )
    export_command = shlex.join(
        [
            "sudo",
            "systemd-run",
            "--quiet",
            "--wait",
            "--pipe",
            "--collect",
            f"--unit={export_unit.removesuffix('.service')}",
            "--service-type=exec",
            "--uid=hermes-agent",
            f"--setenv=HOME={hermes_home}",
            "--property=RuntimeMaxSec=1min",
            "--property=NoNewPrivileges=yes",
            "--property=PrivateTmp=yes",
            "--property=ProtectSystem=strict",
            "--property=ProtectHome=yes",
            f"--property=ReadWritePaths={hermes_home}",
            f"--property=BindReadOnlyPaths={MANAGED_CONFIG_PATH}:{hermes_home}/config.yaml",
            f"--property=EnvironmentFile={token_file}",
            f"--property=BindReadOnlyPaths={MANAGED_POLICY_PATH}:{workspace}/AGENTS.md",
            f"--working-directory={workspace}",
            "--",
            "env",
            f"HERMES_HOME={hermes_home}",
            f"CODEX_HOME={config.get('codex_home', '/var/lib/hermes-agent/codex')}",
            hermes_binary,
            "sessions",
            "export",
            "-",
            "--format",
            "jsonl",
            "--source",
            source_tag,
            "--newer-than",
            "5m",
            "--redact",
        ]
    )
    remote_script = "\n".join(
        [
            "set -eu",
            f"test -f {shlex.quote(MANAGED_POLICY_PATH)}",
            f"test -d {shlex.quote(workspace)}",
            f"if ! test -e {shlex.quote(workspace + '/AGENTS.md')}; then install -o hermes-agent -g hermes-agent -m 0600 /dev/null {shlex.quote(workspace + '/AGENTS.md')}; fi",
            'output_file="$(mktemp)"',
            'error_file="$(mktemp)"',
            'audit_file="$(mktemp)"',
            "trap 'rm -f -- \"$output_file\" \"$error_file\" \"$audit_file\"' EXIT",
            "set +e",
            f"{protected_command} >\"$output_file\" 2>\"$error_file\"",
            "hermes_exit=$?",
            "set -e",
            "audit_complete=false",
            "audit_json='[]'",
            f"if {export_command} >\"$audit_file\"; then",
            "  audit_json=\"$(jq -s -c '.' \"$audit_file\" 2>/dev/null || printf '[]')\"",
            "  audit_complete=true",
            "fi",
            f"printf '{{\"exit_code\":%s,\"audit_complete\":%s,\"source\":%s,\"audit_records\":%s,\"stdout\":' \"$hermes_exit\" \"$audit_complete\" {shlex.quote(json.dumps(source_tag))} \"$audit_json\"",
            "jq -Rs . <\"$output_file\"",
            "printf ',\"stderr\":'",
            "jq -Rs . <\"$error_file\"",
            "printf '}\\n'",
        ]
    )
    remote_command = shlex.join(
        ["sudo", "bash", "-c", remote_script]
    )
    try:
        result = run_command(
            ["ssh", *SSH_OPTIONS, ssh_target(config), remote_command], timeout
        )
    except (Exception, KeyboardInterrupt) as error:
        cleanup_complete, cleanup_failure = cleanup_transient_units(
            config, associated_units, timeout
        )
        error.transient_cleanup_complete = cleanup_complete
        error.transient_cleanup_failure = cleanup_failure
        if not cleanup_complete and cleanup_failure:
            error.add_note(f"transient cleanup failed: {cleanup_failure}")
        raise
    result["associated_units"] = associated_units
    if result["exit_code"] != 0:
        cleanup_complete, cleanup_failure = cleanup_transient_units(
            config, associated_units, timeout
        )
        result["transient_cleanup_complete"] = cleanup_complete
        if cleanup_failure:
            result["transient_cleanup_failure"] = cleanup_failure
        return result
    try:
        payload = checked_json(result, "Hermes invocation audit wrapper")
    except VerificationError as error:
        cleanup_complete, cleanup_failure = cleanup_transient_units(
            config, associated_units, timeout
        )
        error.transient_cleanup_complete = cleanup_complete
        error.transient_cleanup_failure = cleanup_failure
        raise
    payload["stdout"] = redact(payload.get("stdout", ""))
    payload["stderr"] = redact(payload.get("stderr", ""))
    return compact_result(payload)


def cleanup_transient_units(
    config: dict[str, Any], units: list[str], timeout: float
) -> tuple[bool, str | None]:
    """Stop acceptance units and poll their explicit state to a terminal state."""
    cleanup_timeout = max(1.0, min(timeout, 15.0))
    target = ssh_target(config)
    stop_command = shlex.join(["sudo", "systemctl", "stop", *units])
    stop_result = run_command(
        ["ssh", *SSH_OPTIONS, target, stop_command], cleanup_timeout
    )
    unit_arguments = " ".join(shlex.quote(unit) for unit in units)
    deadline_seconds = math.ceil(cleanup_timeout)
    checks = "\n".join(
        [
            "set -u",
            f"deadline=$((SECONDS + {deadline_seconds}))",
            "while :; do",
            "  pending=''",
            f"  for unit in {unit_arguments}; do",
            '    state="$(sudo systemctl show --property=ActiveState --value "$unit")"',
            '    case "$state" in inactive|failed) ;; *) pending="${pending}${pending:+,}${unit}=${state}" ;; esac',
            "  done",
            '  test -z "$pending" && exit 0',
            '  if (( SECONDS >= deadline )); then printf "%s\\n" "$pending" >&2; exit 1; fi',
            "  sleep 0.2",
            "done",
        ]
    )
    wait_result = run_command(
        ["ssh", *SSH_OPTIONS, target, checks], cleanup_timeout + 1.0
    )
    if wait_result["exit_code"] != 0:
        states = redact(wait_result["stderr"]).strip()
        details = "transient units did not reach inactive/failed ActiveState"
        if states:
            details = f"{details}: {states}"
        if stop_result["exit_code"] != 0:
            stop_error = redact(stop_result["stderr"]).strip()
            details = f"{details}; transient unit stop failed: {stop_error}"
        return False, details
    if stop_result["exit_code"] != 0:
        stop_error = redact(stop_result["stderr"]).strip()
        details = "transient unit stop failed"
        if stop_error:
            details = f"{details}: {stop_error}"
        return False, details
    return True, None


def poll(
    check: Any, timeout: float, interval: float, description: str
) -> Any:
    deadline = time.monotonic() + timeout
    last_error = "not observed"
    while time.monotonic() <= deadline:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            value = check(remaining)
            if value:
                return value
            last_error = "observed state did not match"
        except VerificationError as error:
            last_error = str(error)
        time.sleep(min(interval, max(0.0, deadline - time.monotonic())))
    raise VerificationError(f"timeout waiting for {description}: {last_error}")


def write_reports(report: dict[str, Any], report_dir: Path) -> None:
    report_dir.mkdir(parents=True, exist_ok=True)
    json_path = report_dir / "report.json"
    text_path = report_dir / "report.txt"
    write_text_atomic(json_path, json.dumps(report, indent=2, sort_keys=True) + "\n")
    summary = [
        f"status: {report['status']}",
        f"started: {report['started_at']}",
        f"finished: {report.get('finished_at', 'in progress')}",
        f"target: {', '.join(target['label'] for target in report.get('targets', [])) or 'none'}",
        f"report: {json_path}",
    ]
    if report.get("failure"):
        summary.append(f"failure: {report['failure']}")
    write_text_atomic(text_path, "\n".join(summary) + "\n")


def write_text_atomic(path: Path, content: str) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as handle:
        temporary_path = Path(handle.name)
        handle.write(content)
    temporary_path.replace(path)


def default_report_dir() -> Path:
    DEFAULT_REPORT_ROOT.mkdir(parents=True, exist_ok=True)
    prefix = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ-")
    return Path(tempfile.mkdtemp(prefix=prefix, dir=DEFAULT_REPORT_ROOT))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path(os.environ.get("PISERV_HERMES_HOME_APPLE_CONFIG", DEFAULT_CONFIG)))
    parser.add_argument("--report-dir", type=Path)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    parser.add_argument("--poll-interval", type=float, default=DEFAULT_POLL_INTERVAL)
    parser.add_argument("--max-turns", type=int, default=20)
    parser.add_argument("--dry-run", action="store_true", help="Run preflight without changing Home Assistant state")
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    """Reject unsafe acceptance budgets before creating artifacts or probing."""
    if (
        not math.isfinite(args.timeout)
        or args.timeout <= 0
        or args.timeout > MAX_TIMEOUT
    ):
        raise VerificationError(
            f"timeout must be finite and within (0, {MAX_TIMEOUT:g}] seconds"
        )
    if (
        not math.isfinite(args.poll_interval)
        or args.poll_interval <= 0
        or args.poll_interval > MAX_POLL_INTERVAL
        or args.poll_interval > args.timeout
    ):
        raise VerificationError(
            "poll interval must be finite, positive, no greater than "
            f"{MAX_POLL_INTERVAL:g} seconds, and no greater than timeout"
        )
    if args.max_turns <= 0 or args.max_turns > MAX_TURNS:
        raise VerificationError(f"max turns must be within [1, {MAX_TURNS}]")


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
    require_reachable(before_homeclaw, entity["label"])
    before_power = normalize_bool(before_homeclaw["value"])
    desired_power = not before_power
    before_home_assistant_power = home_assistant_power_state(
        before_ha, entity["label"]
    )
    target["before"] = {
        "homeclaw": before_homeclaw,
        "home_assistant_state": before_ha.get("state"),
    }
    target["desired_power"] = desired_power
    if before_home_assistant_power != before_power:
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
    target["action_prompt"] = action_prompt
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
        if target["hermes_restore"].get("transient_cleanup_complete") is False:
            raise VerificationError(
                target["hermes_restore"].get(
                    "transient_cleanup_failure",
                    "timed-out restoration unit cleanup was not confirmed",
                )
            )
        if target["hermes_restore"]["exit_code"] != 0:
            raise VerificationError(f"Hermes cleanup failed for {entity['label']}")
        target["hermes_restore_audit"] = validate_hermes_audit(
            target["hermes_restore"],
            entity["home_assistant_entity_id"],
            f"{entity['label']} restoration",
            "on" if before_power else "off",
        )
        target["restored"] = poll(
            lambda remaining: expected_restore(
                config, entity, original_power, report, remaining
            ),
            args.timeout,
            args.poll_interval,
            f"test entity restoration for {entity['label']}",
        )

    primary_error: BaseException | None = None
    restoration_allowed = True
    timeout_cleanup_error: Exception | None = None
    try:
        mutation_attempted = True
        target["hermes_action"] = invoke_hermes(
            config, action_prompt, args.timeout * 2, args.max_turns
        )
        if target["hermes_action"].get("transient_cleanup_complete") is False:
            restoration_allowed = False
            timeout_cleanup_error = VerificationError(
                target["hermes_action"].get(
                    "transient_cleanup_failure",
                    "timed-out transient unit cleanup was not confirmed",
                )
            )
        if target["hermes_action"]["exit_code"] != 0:
            raise VerificationError(f"Hermes action failed for {entity['label']}")
        target["hermes_action_audit"] = validate_hermes_audit(
            target["hermes_action"],
            entity["home_assistant_entity_id"],
            entity["label"],
            "on" if desired_power else "off",
        )

        def expected_state(remaining: float) -> dict[str, Any] | None:
            attempt_deadline = time.monotonic() + remaining
            homeclaw = homeclaw_state(
                entity["homeclaw_accessory"], entity["homeclaw_characteristic"], remaining
            )
            if homeclaw.get("reachable") is not True:
                return None
            remaining = attempt_deadline - time.monotonic()
            if remaining <= 0:
                return None
            ha, result = remote_home_assistant_state(
                config, entity["home_assistant_entity_id"], remaining
            )
            report["commands"].append(result)
            if home_assistant_power_state(ha, entity["label"]) != desired_power:
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
    except KeyboardInterrupt as error:
        primary_error = error
        if getattr(error, "transient_cleanup_complete", None) is False:
            restoration_allowed = False
            timeout_cleanup_error = VerificationError(
                getattr(
                    error,
                    "transient_cleanup_failure",
                    "transient unit cleanup was not confirmed",
                )
            )
    # Capture unexpected failures so the restoration finally-path still runs.
    except Exception as error:  # noqa: BLE001
        primary_error = error
        if getattr(error, "transient_cleanup_complete", None) is False:
            restoration_allowed = False
            timeout_cleanup_error = VerificationError(
                getattr(
                    error,
                    "transient_cleanup_failure",
                    "transient unit cleanup was not confirmed",
                )
            )
    finally:
        cleanup_error: BaseException | None = None
        if timeout_cleanup_error is not None:
            cleanup_error = timeout_cleanup_error
        elif restoration_allowed:
            try:
                restore()
            # Cleanup must never replace the active primary exception.
            except BaseException as error:  # noqa: BLE001
                cleanup_error = error

    if primary_error is not None:
        target["primary_failure"] = str(primary_error)
    if cleanup_error is not None:
        target["cleanup_failure"] = str(cleanup_error)
    if primary_error is not None or cleanup_error is not None:
        if primary_error is not None and not isinstance(primary_error, Exception):
            if cleanup_error is not None:
                primary_error.add_note(f"cleanup failed: {cleanup_error}")
            raise primary_error
        failures = []
        if primary_error is not None:
            failures.append(f"primary: {primary_error}")
        if cleanup_error is not None:
            failures.append(f"cleanup: {cleanup_error}")
        raise VerificationError("; ".join(failures))


def main() -> int:
    args = parse_args()
    validate_args(args)
    report_dir = args.report_dir or default_report_dir()
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
        if not isinstance(status, dict):
            raise VerificationError("HomeClaw status JSON must be an object")
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
    attempt_deadline = time.monotonic() + timeout
    homeclaw = homeclaw_state(
        entity["homeclaw_accessory"], entity["homeclaw_characteristic"], timeout
    )
    timeout = attempt_deadline - time.monotonic()
    if timeout <= 0:
        return None
    ha, result = remote_home_assistant_state(
        config, entity["home_assistant_entity_id"], timeout
    )
    report["commands"].append(result)
    expected = original_power == "true"
    if homeclaw.get("reachable") is not True:
        return None
    if home_assistant_power_state(ha, entity["label"]) != expected:
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
