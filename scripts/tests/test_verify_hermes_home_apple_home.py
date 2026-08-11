import importlib.util
import json
import math
import os
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch

SCRIPT_PATH = Path(__file__).parents[1] / "verify-hermes-home-apple-home.py"
SPEC = importlib.util.spec_from_file_location("verify_harness", SCRIPT_PATH)
assert SPEC and SPEC.loader
HARNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HARNESS)


class HarnessValidationTests(unittest.TestCase):
    entity_id = "light.test_fixture"

    def test_acceptance_budgets_are_finite_bounded_and_ordered(self):
        valid = (
            (HARNESS.DEFAULT_TIMEOUT, HARNESS.DEFAULT_POLL_INTERVAL),
            (HARNESS.MAX_TIMEOUT, HARNESS.MAX_POLL_INTERVAL),
        )
        invalid = (
            (0.0, 1.0),
            (-1.0, 1.0),
            (math.nan, 1.0),
            (math.inf, 1.0),
            (-math.inf, 1.0),
            (HARNESS.MAX_TIMEOUT + 0.1, 1.0),
            (10.0, 0.0),
            (10.0, -1.0),
            (10.0, math.nan),
            (10.0, math.inf),
            (10.0, HARNESS.MAX_POLL_INTERVAL + 0.1),
            (1.0, 1.1),
        )

        for timeout, poll_interval in valid:
            with self.subTest(valid=(timeout, poll_interval)):
                HARNESS.validate_args(
                    Namespace(
                        timeout=timeout, poll_interval=poll_interval, max_turns=1
                    )
                )
        for timeout, poll_interval in invalid:
            with (
                self.subTest(invalid=(timeout, poll_interval)),
                self.assertRaises(HARNESS.VerificationError),
            ):
                HARNESS.validate_args(
                    Namespace(
                        timeout=timeout, poll_interval=poll_interval, max_turns=1
                    )
                )

    def test_invalid_acceptance_budget_fails_before_report_creation(self):
        args = Namespace(
            timeout=math.inf,
            poll_interval=1.0,
            max_turns=1,
            report_dir=None,
        )
        with (
            patch.object(HARNESS, "parse_args", return_value=args),
            patch.object(HARNESS, "default_report_dir") as report_dir,
            self.assertRaises(HARNESS.VerificationError),
        ):
            HARNESS.main()

        report_dir.assert_not_called()

    def test_excessive_max_turns_fails_before_report_creation(self):
        args = Namespace(
            timeout=1.0,
            poll_interval=1.0,
            max_turns=HARNESS.MAX_TURNS + 1,
            report_dir=None,
        )
        with (
            patch.object(HARNESS, "parse_args", return_value=args),
            patch.object(HARNESS, "default_report_dir") as report_dir,
            patch.object(HARNESS, "homeclaw_json") as homeclaw_json,
            self.assertRaisesRegex(
                HARNESS.VerificationError, "max turns must be within"
            ),
        ):
            HARNESS.main()

        report_dir.assert_not_called()
        homeclaw_json.assert_not_called()

    def test_non_object_homeclaw_status_is_reported(self):
        config = {
            "ssh_target": "admin@PiServ.local",
            "home_assistant_api_url": "http://homeassistant.local:8123",
            "entities": [
                {
                    "label": "fixture",
                    "home_assistant_entity_id": self.entity_id,
                    "homeclaw_accessory": "Fixture",
                    "homeclaw_characteristic": "power",
                    "risk": "non-critical",
                }
            ],
        }
        for status in ([], "ready", 1, True, None):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                config_path = Path(directory) / "config.json"
                config_path.write_text(json.dumps(config), encoding="utf-8")
                args = Namespace(
                    timeout=1.0,
                    poll_interval=1.0,
                    max_turns=1,
                    report_dir=Path(directory) / "report",
                    config=config_path,
                    dry_run=True,
                )
                reports = []
                with (
                    patch.object(HARNESS, "parse_args", return_value=args),
                    patch.object(
                        HARNESS,
                        "homeclaw_json",
                        return_value=(status, {"command": "fixture"}),
                    ),
                    patch.object(
                        HARNESS,
                        "write_reports",
                        side_effect=lambda report, _path, reports=reports: reports.append(
                            report.copy()
                        ),
                    ),
                    patch("builtins.print"),
                ):
                    self.assertEqual(HARNESS.main(), 1)

                self.assertEqual(
                    reports[0]["failure"],
                    "HomeClaw status JSON must be an object",
                )

    def test_non_object_homeclaw_get_payload_is_reported(self):
        for payload in ([], "ready", 1, True, None):
            with self.subTest(payload=payload):
                result = {
                    "exit_code": 0,
                    "stdout": json.dumps(payload),
                    "stderr": "",
                }
                with (
                    patch.object(HARNESS, "run_command", return_value=result),
                    self.assertRaises(HARNESS.VerificationError) as raised,
                ):
                    HARNESS.homeclaw_state("Fixture", "power", 1.0)

                self.assertEqual(
                    str(raised.exception),
                    "homeclaw-cli get 'Fixture' JSON must be an object",
                )

    def test_non_list_homeclaw_services_are_reported(self):
        for services in ({}, "service", 1, True, None):
            with self.subTest(services=services):
                with self.assertRaises(HARNESS.VerificationError) as raised:
                    HARNESS.validate_homeclaw_get_payload(
                        {"services": services}, "Fixture"
                    )

                self.assertEqual(
                    str(raised.exception),
                    "homeclaw-cli get 'Fixture' JSON.services must be a list",
                )

    def test_non_object_homeclaw_service_is_reported(self):
        for service in ([], "service", 1, True, None):
            with self.subTest(service=service):
                with self.assertRaises(HARNESS.VerificationError) as raised:
                    HARNESS.validate_homeclaw_get_payload(
                        {"services": [service]}, "Fixture"
                    )

                self.assertEqual(
                    str(raised.exception),
                    "homeclaw-cli get 'Fixture' JSON.services[0] must be an object",
                )

    def test_non_list_homeclaw_characteristics_are_reported(self):
        for characteristics in ({}, "power", 1, True, None):
            with self.subTest(characteristics=characteristics):
                payload = {"services": [{"characteristics": characteristics}]}
                with self.assertRaises(HARNESS.VerificationError) as raised:
                    HARNESS.validate_homeclaw_get_payload(payload, "Fixture")

                self.assertEqual(
                    str(raised.exception),
                    "homeclaw-cli get 'Fixture' JSON.services[0].characteristics "
                    "must be a list",
                )

    def test_non_object_homeclaw_characteristic_is_reported(self):
        for characteristic in ([], "power", 1, True, None):
            with self.subTest(characteristic=characteristic):
                payload = {"services": [{"characteristics": [characteristic]}]}
                with self.assertRaises(HARNESS.VerificationError) as raised:
                    HARNESS.validate_homeclaw_get_payload(payload, "Fixture")

                self.assertEqual(
                    str(raised.exception),
                    "homeclaw-cli get 'Fixture' JSON.services[0].characteristics[0] "
                    "must be an object",
                )

    def test_non_list_homeclaw_scenes_are_reported(self):
        for scenes in ({}, "scene", 1, True, None):
            with self.subTest(scenes=scenes):
                with self.assertRaises(HARNESS.VerificationError) as raised:
                    HARNESS.validate_homeclaw_scenes_payload(scenes)

                self.assertEqual(
                    str(raised.exception), "homeclaw-cli scenes JSON must be a list"
                )

    def test_non_object_homeclaw_scene_is_reported(self):
        for scene in ([], "Evening", 1, True, None):
            with self.subTest(scene=scene):
                with self.assertRaises(HARNESS.VerificationError) as raised:
                    HARNESS.validate_homeclaw_scenes_payload([scene])

                self.assertEqual(
                    str(raised.exception),
                    "homeclaw-cli scenes JSON[0] must be an object",
                )

    def test_absent_homeclaw_nested_lists_keep_empty_defaults(self):
        self.assertEqual(
            HARNESS.validate_homeclaw_get_payload({}, "Fixture"),
            {},
        )
        self.assertEqual(
            HARNESS.validate_homeclaw_get_payload({"services": [{}]}, "Fixture"),
            {"services": [{}]},
        )

    def test_shared_audit_accepts_two_mutations_and_rejects_three(self):
        mutation = {
            "name": "tool_call",
            "arguments": {
                "name": "mcp__home_assistant_assist__HassTurnOn",
                "arguments": {"name": self.entity_id},
            },
        }

        summary = HARNESS.HERMES_AUDIT.validate_tool_calls(
            [mutation, mutation], self.entity_id, "test fixture", "on"
        )
        self.assertEqual(len(summary["tool_names"]), 2)
        with self.assertRaises(HARNESS.HERMES_AUDIT.AuditError):
            HARNESS.HERMES_AUDIT.validate_tool_calls(
                [mutation, mutation, mutation],
                self.entity_id,
                "test fixture",
                "on",
            )

    def test_exported_session_preserves_mutations_across_records(self):
        mutation = {
            "function": {
                "name": "tool_call",
                "arguments": {
                    "name": "mcp__home_assistant_assist__HassTurnOn",
                    "arguments": {"name": self.entity_id},
                },
            }
        }
        record = {
            "source": "fixture",
            "messages": [{"tool_calls": [mutation]}],
        }

        with self.assertRaises(HARNESS.HERMES_AUDIT.AuditError):
            HARNESS.HERMES_AUDIT.validate_session_export(
                [record, record, record],
                "fixture",
                self.entity_id,
                "test fixture",
                "on",
            )

    def test_home_assistant_unavailable_state_is_rejected(self):
        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.home_assistant_power_state(
                {"state": "unavailable"}, "test fixture"
            )

    def test_poll_passes_only_the_remaining_deadline_to_probe(self):
        observed = []

        def check(remaining):
            observed.append(remaining)
            return "ready"

        with patch.object(HARNESS.time, "monotonic", side_effect=[10.0, 10.25, 10.25]):
            self.assertEqual(HARNESS.poll(check, 1.0, 0.1, "fixture"), "ready")

        self.assertEqual(len(observed), 1)
        self.assertAlmostEqual(observed[0], 0.75)

    def test_restore_probe_reduces_budget_between_sequential_commands(self):
        observed = []
        entity = {
            "label": "fixture",
            "homeclaw_accessory": "Fixture",
            "homeclaw_characteristic": "On",
            "home_assistant_entity_id": self.entity_id,
        }

        def homeclaw_state(_accessory, _characteristic, timeout):
            observed.append(("homeclaw", timeout))
            return {"reachable": True, "value": True}

        def home_assistant_state(_config, _entity_id, timeout):
            observed.append(("home-assistant", timeout))
            return {"state": "on"}, {"command": "fixture"}

        with (
            patch.object(HARNESS.time, "monotonic", side_effect=[10.0, 10.4]),
            patch.object(HARNESS, "homeclaw_state", side_effect=homeclaw_state),
            patch.object(
                HARNESS,
                "remote_home_assistant_state",
                side_effect=home_assistant_state,
            ),
        ):
            result = HARNESS.expected_restore({}, entity, "true", {"commands": []}, 1.0)

        self.assertIsNotNone(result)
        self.assertAlmostEqual(observed[0][1], 1.0)
        self.assertAlmostEqual(observed[1][1], 0.6)

    def test_unreachable_homeclaw_accessory_is_rejected(self):
        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.require_reachable({"reachable": False}, "test fixture")

    def test_piserv_ip_overrides_configured_mdns_target(self):
        config = {"ssh_target": "admin@PiServ.local"}
        with patch.dict(os.environ, {"PISERV_IP": "192.0.2.10"}):
            self.assertEqual(HARNESS.ssh_target(config), "admin@192.0.2.10")

    def test_piserv_ipv6_override_is_bracketed_for_ssh(self):
        config = {"ssh_target": "operator@PiServ.local"}
        with patch.dict(os.environ, {"PISERV_IP": "2001:db8::10"}):
            self.assertEqual(HARNESS.ssh_target(config), "operator@[2001:db8::10]")

    def test_piserv_ip_rejects_non_literal_targets(self):
        config = {"ssh_target": "admin@PiServ.local"}
        invalid_targets = (
            "",
            "piserv.example.com",
            "operator@192.0.2.10",
            " 192.0.2.10",
            "192.0.2.10 ",
            "192.0.2.10/24",
            "-oProxyCommand=fixture",
        )

        for target in invalid_targets:
            with (
                self.subTest(target=target),
                patch.dict(os.environ, {"PISERV_IP": target}),
                self.assertRaises(HARNESS.VerificationError),
            ):
                HARNESS.ssh_target(config)

    def test_configured_ssh_target_accepts_supported_forms(self):
        valid_targets = (
            "PiServ.local",
            "admin@host-name.example",
            "admin@192.0.2.10",
            "operator@[2001:db8::10]",
            "user_name@host.example.",
        )

        for target in valid_targets:
            with self.subTest(target=target), patch.dict(os.environ, {}, clear=True):
                self.assertEqual(HARNESS.ssh_target({"ssh_target": target}), target)

    def test_configured_ssh_target_rejects_ambiguous_or_option_shaped_forms(self):
        invalid_targets = (
            "",
            " PiServ.local",
            "PiServ.local ",
            "PiServ local",
            "-oProxyCommand=fixture",
            "admin@-oProxyCommand=fixture",
            "@PiServ.local",
            "bad user@PiServ.local",
            "admin@@PiServ.local",
            "admin@PiServ.local:22",
            "admin@192.0.2.10/24",
            "admin@999.999.999.999",
            "admin@2001:db8::10",
            "admin@[fe80::1%eth0]",
            "admin@[192.0.2.10]",
            "admin@[2001:db8::10]:22",
            "admin@host_name.example",
            "admin@.example",
            "admin@example..com",
            "admin@-host.example",
            "admin@host-.example",
        )

        for target in invalid_targets:
            with (
                self.subTest(target=target),
                patch.dict(os.environ, {}, clear=True),
                self.assertRaises(HARNESS.VerificationError),
            ):
                HARNESS.ssh_target({"ssh_target": target})

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
                            "arguments": {"name": self.entity_id},
                        }
                    ),
                },
            ],
        }
        audit = HARNESS.validate_hermes_audit(
            invocation, self.entity_id, "test fixture"
        )
        self.assertEqual(audit["entity_ids"], [self.entity_id])

    def test_hermes_audit_rejects_non_exact_mutation_arguments(self):
        invalid_arguments = (
            {"name": "light.other_fixture"},
            {"name": self.entity_id, "domain": "light"},
            {"name": [self.entity_id]},
            {"name": {"entity_id": self.entity_id}},
            {"entity_id": self.entity_id},
            {"area": "all"},
            {"domain": "light"},
            {"name": self.entity_id, "selector": {"area": "all"}},
            {},
        )

        for arguments in invalid_arguments:
            invocation = {
                "audit_complete": True,
                "tool_calls": [
                    {
                        "name": "tool_call",
                        "arguments": {
                            "name": "mcp__home_assistant_assist__HassTurnOff",
                            "arguments": arguments,
                        },
                    }
                ],
            }
            with (
                self.subTest(arguments=arguments),
                self.assertRaises(HARNESS.VerificationError),
            ):
                HARNESS.validate_hermes_audit(
                    invocation, self.entity_id, "test fixture"
                )

    def test_hermes_audit_rejects_wrong_mutation_direction(self):
        invocation = {
            "audit_complete": True,
            "tool_calls": [
                {
                    "name": "tool_call",
                    "arguments": {
                        "name": "mcp__home_assistant_assist__HassTurnOn",
                        "arguments": {"name": self.entity_id},
                    },
                }
            ],
        }
        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.validate_hermes_audit(
                invocation, self.entity_id, "test fixture", "off"
            )

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
                        "arguments": {"name": self.entity_id},
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
        self.assertEqual(remote_command.count("BindReadOnlyPaths="), 4)
        self.assertIn(HARNESS.MANAGED_POLICY_PATH, remote_command)
        self.assertEqual(remote_command.count(HARNESS.MANAGED_CONFIG_PATH), 2)
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
        self.assertIn("systemctl show --property=ActiveState --value", wait_command)
        self.assertIn("inactive|failed", wait_command)
        self.assertIn("SECONDS >= deadline", wait_command)
        self.assertTrue(result["transient_cleanup_complete"])

    def test_cleanup_rejects_nonterminal_explicit_active_state(self):
        stopped = {"exit_code": 0, "stdout": "", "stderr": ""}
        still_active = {
            "exit_code": 1,
            "stdout": "",
            "stderr": "fixture.service=deactivating",
        }
        with patch.object(
            HARNESS, "run_command", side_effect=[stopped, still_active]
        ):
            complete, failure = HARNESS.cleanup_transient_units(
                {"ssh_target": "admin@PiServ.local"}, ["fixture.service"], 2
            )

        self.assertFalse(complete)
        self.assertIn("inactive/failed ActiveState", failure)
        self.assertIn("fixture.service=deactivating", failure)

    def test_cleanup_propagates_stop_failure_after_terminal_state(self):
        stop_failed = {
            "exit_code": 1,
            "stdout": "",
            "stderr": "stop transport failed",
            "timed_out": False,
        }
        terminal = {
            "exit_code": 0,
            "stdout": "",
            "stderr": "",
            "timed_out": False,
        }
        with patch.object(
            HARNESS, "run_command", side_effect=[stop_failed, terminal]
        ):
            complete, failure = HARNESS.cleanup_transient_units(
                {"ssh_target": "admin@PiServ.local"}, ["fixture.service"], 2
            )

        self.assertFalse(complete)
        self.assertIn("transient unit stop failed", failure)
        self.assertIn("stop transport failed", failure)

    def test_nonzero_ssh_result_cleans_associated_units(self):
        failed = {
            "exit_code": 255,
            "stdout": "",
            "stderr": "connection lost",
            "timed_out": False,
        }
        with (
            patch.object(HARNESS, "run_command", return_value=failed),
            patch.object(
                HARNESS, "cleanup_transient_units", return_value=(True, None)
            ) as cleanup,
        ):
            result = HARNESS.invoke_hermes(
                {"ssh_target": "admin@PiServ.local"}, "test", 10, 1
            )

        self.assertEqual(result["exit_code"], 255)
        self.assertTrue(result["transient_cleanup_complete"])
        self.assertEqual(cleanup.call_count, 1)
        self.assertEqual(cleanup.call_args.args[1], result["associated_units"])

    def test_invalid_wrapper_output_cleans_before_raising(self):
        incomplete = {
            "exit_code": 0,
            "stdout": "not-json",
            "stderr": "",
            "timed_out": False,
        }
        with (
            patch.object(HARNESS, "run_command", return_value=incomplete),
            patch.object(
                HARNESS,
                "cleanup_transient_units",
                return_value=(False, "unit remained activating"),
            ) as cleanup,
            self.assertRaises(HARNESS.VerificationError) as raised,
        ):
            HARNESS.invoke_hermes(
                {"ssh_target": "admin@PiServ.local"}, "test", 10, 1
            )

        self.assertEqual(cleanup.call_count, 1)
        self.assertFalse(raised.exception.transient_cleanup_complete)
        self.assertEqual(
            raised.exception.transient_cleanup_failure,
            "unit remained activating",
        )

    def test_valid_wrapper_completion_does_not_force_cleanup(self):
        complete = {
            "exit_code": 0,
            "stdout": '{"exit_code":3,"stdout":"","stderr":"failed"}',
            "stderr": "",
            "timed_out": False,
        }
        with (
            patch.object(HARNESS, "run_command", return_value=complete),
            patch.object(HARNESS, "cleanup_transient_units") as cleanup,
        ):
            result = HARNESS.invoke_hermes(
                {"ssh_target": "admin@PiServ.local"}, "test", 10, 1
            )

        self.assertEqual(result["exit_code"], 3)
        cleanup.assert_not_called()

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

    def test_malformed_homeclaw_convergence_and_restoration_are_attributed(self):
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
        initial = {
            "reachable": True,
            "services": [
                {"characteristics": [{"name": "On", "value": False}]}
            ],
        }
        homeclaw_payloads = [
            (initial, {"command": "initial"}),
            ({"services": {}}, {"command": "convergence"}),
            (
                {"services": [{"characteristics": {}}]},
                {"command": "restoration"},
            ),
        ]

        with (
            patch.object(HARNESS, "homeclaw_json", side_effect=homeclaw_payloads),
            patch.object(
                HARNESS,
                "remote_home_assistant_state",
                return_value=({"state": "off"}, {"exit_code": 0}),
            ),
            patch.object(HARNESS, "invoke_hermes", return_value={"exit_code": 0}),
            patch.object(HARNESS, "validate_hermes_audit", return_value={}),
            patch.object(
                HARNESS, "poll", side_effect=lambda callback, *_args: callback(1.0)
            ),
            self.assertRaises(HARNESS.VerificationError) as raised,
        ):
            HARNESS.verify_entity({}, entity, args, report)

        convergence_failure = (
            "homeclaw-cli get 'Test Fixture' JSON.services must be a list"
        )
        restoration_failure = (
            "homeclaw-cli get 'Test Fixture' JSON.services[0].characteristics "
            "must be a list"
        )
        self.assertEqual(
            str(raised.exception),
            f"primary: {convergence_failure}; cleanup: {restoration_failure}",
        )
        self.assertEqual(report["targets"][0]["primary_failure"], convergence_failure)
        self.assertEqual(report["targets"][0]["cleanup_failure"], restoration_failure)

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

    def test_session_audit_records_are_scrubbed_from_report_state(self):
        source = "acceptance-source"
        private_value = "private-session-value"
        valid_call = {
            "function": {
                "name": "tool_call",
                "arguments": {
                    "name": "mcp__home_assistant_assist__HassTurnOn",
                    "arguments": {"name": self.entity_id},
                },
            }
        }

        for rejected in (False, True):
            with self.subTest(rejected=rejected):
                records = [
                    {
                        "source": source,
                        "private_field": private_value,
                        "messages": [{"tool_calls": [valid_call]}],
                    }
                ]
                if rejected:
                    records.append({"source": "sibling-source", "messages": []})
                invocation = {
                    "audit_complete": True,
                    "source": source,
                    "audit_records": records,
                }
                target = {"hermes_action": invocation}

                if rejected:
                    with self.assertRaises(HARNESS.VerificationError):
                        HARNESS.validate_hermes_audit(
                            invocation, self.entity_id, "fixture", "on"
                        )
                else:
                    target["hermes_action_audit"] = HARNESS.validate_hermes_audit(
                        invocation, self.entity_id, "fixture", "on"
                    )
                    self.assertEqual(
                        target["hermes_action_audit"]["entity_ids"], [self.entity_id]
                    )

                report_state = json.dumps({"targets": [target]}, sort_keys=True)
                self.assertNotIn("audit_records", invocation)
                self.assertNotIn("audit_records", report_state)
                self.assertNotIn("private_field", report_state)
                self.assertNotIn(private_value, report_state)

    def test_session_export_rejects_missing_function_record(self):
        source = "acceptance-source"
        valid_call = {
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
                {
                    "source": source,
                    "messages": [{"tool_calls": [valid_call, {}]}],
                }
            ],
        }

        with self.assertRaises(HARNESS.VerificationError):
            HARNESS.validate_hermes_audit(invocation, self.entity_id, "fixture")

    def test_interrupted_invocation_stops_exact_transient_units(self):
        config = {"ssh_target": "admin@PiServ.local"}
        with (
            patch.object(HARNESS, "run_command", side_effect=KeyboardInterrupt),
            patch.object(
                HARNESS,
                "cleanup_transient_units",
                return_value=(True, None),
            ) as cleanup,
            self.assertRaises(KeyboardInterrupt),
        ):
            HARNESS.invoke_hermes(config, "fixture", 1.0, 1)

        units = cleanup.call_args.args[1]
        self.assertEqual(len(units), 2)
        self.assertTrue(all(unit.startswith("piserv-hermes-") for unit in units))

    def test_keyboard_interrupt_still_attempts_restoration(self):
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
        primary_error = KeyboardInterrupt()
        primary_error.transient_cleanup_complete = True
        primary_error.transient_cleanup_failure = None
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
                side_effect=[primary_error, ValueError("cleanup attempted")],
            ) as invoke_hermes,
            self.assertRaises(KeyboardInterrupt),
        ):
            HARNESS.verify_entity({}, entity, args, report)

        self.assertEqual(invoke_hermes.call_count, 2)

    def test_failed_keyboard_interrupt_cleanup_prohibits_restoration(self):
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
        primary_error = KeyboardInterrupt()
        primary_error.transient_cleanup_complete = False
        primary_error.transient_cleanup_failure = "units remained active"
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
                HARNESS, "invoke_hermes", side_effect=primary_error
            ) as invoke_hermes,
            self.assertRaises(KeyboardInterrupt) as raised,
        ):
            HARNESS.verify_entity({}, entity, args, report)

        self.assertEqual(invoke_hermes.call_count, 1)
        self.assertEqual(
            raised.exception.__notes__,
            ["cleanup failed: units remained active"],
        )

    def test_failed_exception_cleanup_prohibits_restoration(self):
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
        primary_error = OSError("primary transport")
        primary_error.transient_cleanup_complete = False
        primary_error.transient_cleanup_failure = "units remained active"
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
                HARNESS, "invoke_hermes", side_effect=primary_error
            ) as invoke_hermes,
            self.assertRaisesRegex(
                HARNESS.VerificationError,
                "primary: primary transport; cleanup: units remained active",
            ),
        ):
            HARNESS.verify_entity({}, entity, args, report)

        self.assertEqual(invoke_hermes.call_count, 1)

    def test_successful_exception_cleanup_allows_restoration(self):
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
        primary_error = OSError("primary transport")
        primary_error.transient_cleanup_complete = True
        primary_error.transient_cleanup_failure = None
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
                side_effect=[primary_error, ValueError("cleanup attempted")],
            ) as invoke_hermes,
            self.assertRaisesRegex(
                HARNESS.VerificationError,
                "primary: primary transport; cleanup: cleanup attempted",
            ),
        ):
            HARNESS.verify_entity({}, entity, args, report)

        self.assertEqual(invoke_hermes.call_count, 2)

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
        self.assertIn(self.entity_id, report["targets"][0]["action_prompt"])


if __name__ == "__main__":
    unittest.main()
