import importlib.util
import json
import os
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
        self.assertIn("cd /srv/hermes/workspace", remote_command)


if __name__ == "__main__":
    unittest.main()
