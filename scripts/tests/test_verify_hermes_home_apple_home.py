import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT_PATH = Path(__file__).parents[1] / "verify-hermes-home-apple-home.py"
SPEC = importlib.util.spec_from_file_location("verify_harness", SCRIPT_PATH)
assert SPEC and SPEC.loader
HARNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HARNESS)


class HarnessValidationTests(unittest.TestCase):
    entity_id = "light.test_fixture"

    def test_home_assistant_unavailable_state_is_rejected(self):
        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.home_assistant_power_state(
                {"state": "unavailable"}, "test fixture"
            )

    def test_unreachable_homeclaw_accessory_is_rejected(self):
        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.require_reachable({"reachable": False}, "test fixture")

    def test_piserv_ip_overrides_configured_mdns_target(self):
        config = {"ssh_target": "admin@PiServ.local"}
        with patch.dict(os.environ, {"PISERV_IP": "192.0.2.10"}):
            self.assertEqual(HARNESS.ssh_target(config), "admin@192.0.2.10")

    def test_hermes_audit_accepts_only_the_named_entity(self):
        invocation = {
            "audit_complete": True,
            "tool_calls": [
                {
                    "name": "tool_describe",
                    "arguments": json.dumps(
                        {"name": "mcp__home_assistant_assist__HassTurnOff"}
                    ),
                },
                {
                    "name": "tool_call",
                    "arguments": json.dumps(
                        {
                            "name": "mcp__home_assistant_assist__HassTurnOff",
                            "arguments": {"name": self.entity_id, "domain": "light"},
                        }
                    ),
                },
            ],
        }
        audit = HARNESS.validate_hermes_audit(
            invocation, self.entity_id, "test fixture"
        )
        self.assertEqual(audit["entity_ids"], [self.entity_id])

    def test_hermes_audit_rejects_a_sibling_entity(self):
        invocation = {
            "audit_complete": True,
            "tool_calls": [
                {
                    "name": "tool_call",
                    "arguments": {
                        "name": "mcp__home_assistant_assist__HassTurnOff",
                        "arguments": {"name": "light.other_fixture", "domain": "light"},
                    },
                }
            ],
        }
        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.validate_hermes_audit(invocation, self.entity_id, "test fixture")

    def test_hermes_audit_allows_context_without_entity_arguments(self):
        invocation = {
            "audit_complete": True,
            "tool_calls": [
                {
                    "name": "tool_call",
                    "arguments": {
                        "name": "mcp__home_assistant_assist__GetLiveContext",
                        "arguments": {},
                    },
                },
                {
                    "name": "tool_call",
                    "arguments": {
                        "name": "mcp__home_assistant_assist__HassTurnOn",
                        "arguments": {"name": self.entity_id, "domain": "light"},
                    },
                },
            ],
        }

        audit = HARNESS.validate_hermes_audit(
            invocation, self.entity_id, "test fixture"
        )

        self.assertEqual(
            audit["tool_names"],
            [
                "mcp__home_assistant_assist__GetLiveContext",
                "mcp__home_assistant_assist__HassTurnOn",
            ],
        )

    def test_hermes_audit_rejects_unknown_tool(self):
        invocation = {
            "audit_complete": True,
            "tool_calls": [
                {
                    "name": "tool_call",
                    "arguments": {
                        "name": "mcp__home_assistant_assist__HassDeleteEverything",
                        "arguments": {"name": self.entity_id},
                    },
                }
            ],
        }

        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.validate_hermes_audit(invocation, self.entity_id, "test fixture")

    def test_hermes_audit_rejects_malformed_called_arguments(self):
        invocation = {
            "audit_complete": True,
            "tool_calls": [
                {
                    "name": "tool_call",
                    "arguments": {
                        "name": "mcp__home_assistant_assist__HassTurnOff",
                        "arguments": "not-json-object",
                    },
                }
            ],
        }

        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.validate_hermes_audit(invocation, self.entity_id, "test fixture")

    def test_hermes_audit_rejects_context_without_mutation(self):
        invocation = {
            "audit_complete": True,
            "tool_calls": [
                {
                    "name": "tool_call",
                    "arguments": {
                        "name": "mcp__home_assistant_assist__GetLiveContext",
                        "arguments": {},
                    },
                }
            ],
        }

        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.validate_hermes_audit(invocation, self.entity_id, "test fixture")

    def test_hermes_invocation_uses_configured_binary_for_audit_export(self):
        result = {
            "exit_code": 0,
            "stdout": '{"exit_code":0,"audit_complete":true,"tool_calls":[],"stdout":"","stderr":""}\n',
            "stderr": "",
        }
        with patch.object(HARNESS, "run_command", return_value=result) as run_command:
            HARNESS.invoke_hermes(
                {
                    "hermes_binary": "/opt/hermes/bin/hermes",
                    "hermes_home": "/srv/hermes",
                    "ssh_target": "admin@PiServ.local",
                },
                "Respond with exactly OK.",
                10,
                1,
            )

        remote_command = run_command.call_args.args[0][-1]
        self.assertIn("/opt/hermes/bin/hermes sessions export", remote_command)
        self.assertIn("--working-directory=/srv/hermes/workspace", remote_command)
        self.assertEqual(remote_command.count("ProtectSystem=strict"), 2)
        self.assertEqual(remote_command.count("NoNewPrivileges=yes"), 2)
        self.assertEqual(remote_command.count("BindReadOnlyPaths="), 2)
        self.assertIn(HARNESS.MANAGED_POLICY_PATH, remote_command)
        self.assertNotIn("set -a", remote_command)
        self.assertNotIn(". /var/lib/hermes-agent/home-assistant-mcp.env", remote_command)
        self.assertEqual(remote_command.count("--property=EnvironmentFile="), 2)
        self.assertRegex(remote_command, r"--unit=piserv-hermes-action-[0-9a-f]{16}")
        self.assertRegex(remote_command, r"--unit=piserv-hermes-export-[0-9a-f]{16}")

    def test_home_assistant_state_injects_token_only_through_systemd(self):
        result = {"exit_code": 0, "stdout": '{"state":"off"}', "stderr": ""}
        with patch.object(HARNESS, "run_command", return_value=result) as run_command:
            HARNESS.remote_home_assistant_state(
                {
                    "ssh_target": "admin@PiServ.local",
                    "home_assistant_api_url": "http://homeassistant.local:8123/api",
                },
                self.entity_id,
                10,
            )

        remote_command = run_command.call_args.args[0][-1]
        self.assertIn("--uid=hermes-agent", remote_command)
        self.assertIn("--property=EnvironmentFile=", remote_command)
        self.assertNotIn("set -a", remote_command)
        self.assertNotIn(". /var/lib/hermes-agent/home-assistant-mcp.env", remote_command)

    def test_timeout_stops_and_waits_for_exact_associated_units(self):
        timed_out = {
            "exit_code": None,
            "stdout": "",
            "stderr": "timed out",
            "timed_out": True,
        }
        success = {"exit_code": 0, "stdout": "", "stderr": "", "timed_out": False}
        with (
            patch.object(HARNESS.time, "time_ns", return_value=123456789),
            patch.object(HARNESS.os, "getpid", return_value=42),
            patch.object(
                HARNESS, "run_command", side_effect=[timed_out, success, success]
            ) as run_command,
        ):
            result = HARNESS.invoke_hermes(
                {"ssh_target": "admin@PiServ.local"}, "test", 10, 1
            )

        digest = HARNESS.hashlib.sha256(
            b"piserv-home-apple-123456789-42"
        ).hexdigest()[:16]
        units = [
            f"piserv-hermes-action-{digest}.service",
            f"piserv-hermes-export-{digest}.service",
        ]
        stop_command = run_command.call_args_list[1].args[0][-1]
        wait_command = run_command.call_args_list[2].args[0][-1]
        self.assertEqual(stop_command, HARNESS.shlex.join(["sudo", "systemctl", "stop", *units]))
        for unit in units:
            self.assertIn(HARNESS.shlex.quote(unit), wait_command)
        self.assertTrue(result["transient_cleanup_complete"])

    def test_restoration_is_gated_on_failed_timeout_cleanup(self):
        entity = {
            "label": "test fixture",
            "home_assistant_entity_id": self.entity_id,
            "homeclaw_accessory": "Test Fixture",
            "homeclaw_characteristic": "On",
        }
        args = type(
            "Args",
            (),
            {"timeout": 1.0, "poll_interval": 0.1, "max_turns": 1, "dry_run": False},
        )()
        report = {"targets": [], "commands": []}
        action = {
            "exit_code": None,
            "timed_out": True,
            "transient_cleanup_complete": False,
            "transient_cleanup_failure": "units remained active",
        }
        with (
            patch.object(HARNESS, "homeclaw_state", return_value={"reachable": True, "value": False}),
            patch.object(HARNESS, "remote_home_assistant_state", return_value=({"state": "off"}, {"exit_code": 0})),
            patch.object(HARNESS, "invoke_hermes", return_value=action) as invoke_hermes,
            self.assertRaisesRegex(HARNESS.VerificationError, "cleanup: units remained active"),
        ):
            HARNESS.verify_entity({}, entity, args, report)

        self.assertEqual(invoke_hermes.call_count, 1)
        target = report["targets"][0]
        self.assertIn("Hermes action failed", target["primary_failure"])
        self.assertEqual(target["cleanup_failure"], "units remained active")

    def test_source_scoped_session_export_rejects_mixed_sources(self):
        source = "acceptance-source"
        call = {
            "function": {
                "name": "tool_call",
                "arguments": {
                    "name": "mcp__home_assistant_assist__HassTurnOn",
                    "arguments": {"name": self.entity_id},
                },
            }
        }
        invocation = {
            "audit_complete": True,
            "source": source,
            "audit_records": [
                {"source": source, "messages": [{"tool_calls": [call]}]},
                {"source": "sibling-source", "messages": []},
            ],
        }

        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.validate_hermes_audit(invocation, self.entity_id, "fixture")

    def test_default_report_directories_are_unique(self):
        with (
            tempfile.TemporaryDirectory() as temporary_root,
            patch.object(HARNESS, "DEFAULT_REPORT_ROOT", Path(temporary_root)),
        ):
            first = HARNESS.default_report_dir()
            second = HARNESS.default_report_dir()

        self.assertNotEqual(first, second)

    def test_primary_and_cleanup_operational_failures_are_both_reported(self):
        entity = {
            "label": "test fixture",
            "home_assistant_entity_id": self.entity_id,
            "homeclaw_accessory": "Test Fixture",
            "homeclaw_characteristic": "On",
        }
        args = type(
            "Args",
            (),
            {"timeout": 1.0, "poll_interval": 0.1, "max_turns": 1, "dry_run": False},
        )()
        report = {"targets": [], "commands": []}
        with (
            patch.object(
                HARNESS,
                "homeclaw_state",
                return_value={"reachable": True, "value": False},
            ),
            patch.object(
                HARNESS,
                "remote_home_assistant_state",
                return_value=({"state": "off"}, {"exit_code": 0}),
            ),
            patch.object(
                HARNESS,
                "invoke_hermes",
                side_effect=[OSError("primary transport"), ValueError("cleanup payload")],
            ),
            self.assertRaisesRegex(
                HARNESS.VerificationError,
                "primary: primary transport; cleanup: cleanup payload",
            ),
        ):
            HARNESS.verify_entity({}, entity, args, report)

        self.assertEqual(report["targets"][0]["primary_failure"], "primary transport")
        self.assertEqual(report["targets"][0]["cleanup_failure"], "cleanup payload")


if __name__ == "__main__":
    unittest.main()
