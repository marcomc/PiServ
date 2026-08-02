#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import py_compile
import subprocess
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest.mock import ANY, call, patch


ROLE_DIRECTORY = Path(__file__).resolve().parent.parent
TEMPLATE_PATH = ROLE_DIRECTORY / "templates" / "piserv-shutdown-notify.py.j2"
SERVICE_TEMPLATE_PATH = ROLE_DIRECTORY / "templates" / "piserv-shutdown-notify.service.j2"
TASKS_PATH = ROLE_DIRECTORY / "tasks" / "shutdown-notification.yml"


def load_notification_module() -> object:
    template = TEMPLATE_PATH.read_text(encoding="utf-8")
    rendered = template.replace(
        "{{ base_shutdown_notification_recipient | to_json }}", '"root"'
    ).replace(
        "{{ base_shutdown_notification_subject_prefix | to_json }}", '"[PiServ]"'
    ).replace(
        "{{ base_shutdown_notification_condition_path | to_json }}", '"/etc/msmtprc"'
    )
    with tempfile.TemporaryDirectory() as temporary_directory:
        script_path = Path(temporary_directory) / "piserv-shutdown-notify"
        script_path.write_text(rendered, encoding="utf-8")
        py_compile.compile(str(script_path), doraise=True)
        loader = SourceFileLoader("piserv_shutdown_notify", str(script_path))
        specification = importlib.util.spec_from_loader(
            "piserv_shutdown_notify", loader
        )
        if specification is None or specification.loader is None:
            raise RuntimeError("could not load the rendered shutdown notification helper")
        module = importlib.util.module_from_spec(specification)
        sys.modules[specification.name] = module
        specification.loader.exec_module(module)
        return module


def render_service_template(condition_path: str = "/etc/msmtprc") -> str:
    with tempfile.TemporaryDirectory() as temporary_directory:
        temporary_path = Path(temporary_directory)
        output_path = temporary_path / "piserv-shutdown-notify.service"
        playbook_path = temporary_path / "render-service.yml"
        playbook_path.write_text(
            "\n".join(
                [
                    "---",
                    "- name: Render shutdown notification service",
                    "  hosts: localhost",
                    "  gather_facts: false",
                    "  tasks:",
                    "    - name: Render service",
                    "      ansible.builtin.template:",
                    f"        src: {json.dumps(str(SERVICE_TEMPLATE_PATH))}",
                    f"        dest: {json.dumps(str(output_path))}",
                    "      vars:",
                    "        base_shutdown_notification_condition_path: "
                    + json.dumps(condition_path),
                    "        base_shutdown_notification_script_path: >-",
                    "          /opt/PiServ helpers/piserv-shutdown-notify",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        subprocess.run(
            [
                "ansible-playbook",
                "-i",
                "localhost,",
                "-c",
                "local",
                str(playbook_path),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        return output_path.read_text(encoding="utf-8")


class ShutdownNotificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.notification = load_notification_module()

    def logind_record(
        self,
        monotonic: int = 10_000_000,
        realtime: int = 1_760_000_001_000_000,
    ) -> dict[str, object]:
        return {
            "_COMM": "systemd-logind",
            "_EXE": "/usr/lib/systemd/systemd-logind",
            "MESSAGE_ID": "98268866d1d54a499c4e98921d93bc40",
            "__MONOTONIC_TIMESTAMP": str(monotonic),
            "_SOURCE_REALTIME_TIMESTAMP": str(realtime),
        }

    def sudo_record(
        self,
        command: str,
        monotonic: int = 9_000_000,
        realtime: int = 1_760_000_000_000_000,
        user: str = "admin",
    ) -> dict[str, object]:
        return {
            "_COMM": "sudo",
            "_EXE": "/usr/bin/sudo",
            "__MONOTONIC_TIMESTAMP": str(monotonic),
            "_SOURCE_REALTIME_TIMESTAMP": str(realtime),
            "MESSAGE": (
                f"{user} : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                f"COMMAND={command}"
            ),
        }

    def test_immediate_direct_command_is_correlated(self) -> None:
        evidence = self.notification.correlate_shutdown_evidence(
            [self.sudo_record("/usr/sbin/reboot"), self.logind_record()]
        )

        self.assertIsNotNone(evidence)
        self.assertEqual(evidence.sudo_user, "admin")
        self.assertEqual(evidence.command, "/usr/sbin/reboot")
        self.assertEqual(evidence.sudo_evidence_at, "2025-10-09T08:53:20+00:00")
        self.assertEqual(evidence.shutdown_event_at, "2025-10-09T08:53:21+00:00")

    def test_ansible_shell_wrapped_command_is_preserved_without_cli_parsing(self) -> None:
        command = (
            "/bin/sh -c 'echo BECOME-SUCCESS-abc ; "
            "/sbin/shutdown -r now && sleep 0'"
        )

        evidence = self.notification.correlate_shutdown_evidence(
            [self.sudo_record(command), self.logind_record()]
        )

        self.assertIsNotNone(evidence)
        self.assertEqual(evidence.command, command)

    def test_nearby_unrelated_sudo_is_labeled_as_correlation_not_cause(self) -> None:
        evidence = self.notification.correlate_shutdown_evidence(
            [self.sudo_record("/usr/bin/apt-get update"), self.logind_record()]
        )

        payload = self.notification.notification_payload("PiServ.local", evidence)

        self.assertIn("Nearby sudo command: /usr/bin/apt-get update", payload)
        self.assertIn("temporal correlation is not proof", payload)
        self.assertNotIn("Requested by", payload)

    def test_scheduled_command_outside_window_is_unknown(self) -> None:
        evidence = self.notification.correlate_shutdown_evidence(
            [
                self.sudo_record("/sbin/shutdown -r +10", monotonic=4_999_999),
                self.logind_record(monotonic=10_000_000),
            ]
        )

        self.assertIsNone(evidence)

    def test_record_at_five_second_boundary_is_correlated(self) -> None:
        evidence = self.notification.correlate_shutdown_evidence(
            [
                self.sudo_record("/usr/sbin/reboot", monotonic=5_000_000),
                self.logind_record(monotonic=10_000_000),
            ]
        )

        self.assertIsNotNone(evidence)

    def test_record_at_same_monotonic_time_does_not_precede_event(self) -> None:
        evidence = self.notification.correlate_shutdown_evidence(
            [
                self.sudo_record("/usr/sbin/reboot", monotonic=10_000_000),
                self.logind_record(monotonic=10_000_000),
            ]
        )

        self.assertIsNone(evidence)

    def test_record_after_shutdown_event_is_unknown(self) -> None:
        evidence = self.notification.correlate_shutdown_evidence(
            [
                self.logind_record(monotonic=10_000_000),
                self.sudo_record("/usr/sbin/reboot", monotonic=10_000_001),
            ]
        )

        self.assertIsNone(evidence)

    def test_forged_sudo_identity_is_rejected(self) -> None:
        for field, forged_value in (
            ("_COMM", "logger"),
            ("_EXE", "/usr/bin/logger"),
        ):
            with self.subTest(field=field):
                sudo_record = self.sudo_record("/usr/sbin/reboot")
                sudo_record[field] = forged_value
                evidence = self.notification.correlate_shutdown_evidence(
                    [sudo_record, self.logind_record()]
                )
                self.assertIsNone(evidence)

    def test_forged_logind_identity_or_message_id_is_rejected(self) -> None:
        for field, forged_value in (
            ("_COMM", "logger"),
            ("_EXE", "/usr/bin/logger"),
            ("MESSAGE_ID", "forged"),
        ):
            with self.subTest(field=field):
                logind_record = self.logind_record()
                logind_record[field] = forged_value
                evidence = self.notification.correlate_shutdown_evidence(
                    [self.sudo_record("/usr/sbin/reboot"), logind_record]
                )
                self.assertIsNone(evidence)

    def test_missing_monotonic_timestamp_is_unknown(self) -> None:
        for missing_from in ("sudo", "logind"):
            with self.subTest(missing_from=missing_from):
                sudo_record = self.sudo_record("/usr/sbin/reboot")
                logind_record = self.logind_record()
                target = sudo_record if missing_from == "sudo" else logind_record
                target.pop("__MONOTONIC_TIMESTAMP")
                evidence = self.notification.correlate_shutdown_evidence(
                    [sudo_record, logind_record]
                )
                self.assertIsNone(evidence)

    def test_no_logind_shutdown_event_is_unknown(self) -> None:
        evidence = self.notification.correlate_shutdown_evidence(
            [self.sudo_record("/usr/sbin/reboot")]
        )

        self.assertIsNone(evidence)

    def test_latest_event_and_nearest_preceding_sudo_record_are_selected(self) -> None:
        records = [
            self.sudo_record("/usr/sbin/reboot old", monotonic=9_000_000),
            self.logind_record(monotonic=10_000_000),
            self.sudo_record("/usr/bin/apt-get update", monotonic=18_000_000),
            self.sudo_record("/usr/bin/systemctl reboot", monotonic=19_500_000),
            self.logind_record(monotonic=20_000_000),
        ]

        evidence = self.notification.correlate_shutdown_evidence(records)

        self.assertIsNotNone(evidence)
        self.assertEqual(evidence.command, "/usr/bin/systemctl reboot")

    def test_monotonic_time_controls_order_despite_realtime_clock_correction(self) -> None:
        evidence = self.notification.correlate_shutdown_evidence(
            [
                self.sudo_record(
                    "/usr/sbin/reboot",
                    monotonic=9_000_000,
                    realtime=1_760_000_002_000_000,
                ),
                self.logind_record(
                    monotonic=10_000_000,
                    realtime=1_760_000_001_000_000,
                ),
            ]
        )

        self.assertIsNotNone(evidence)
        self.assertEqual(evidence.command, "/usr/sbin/reboot")

    def test_reception_realtime_is_used_for_display_when_source_time_is_absent(
        self,
    ) -> None:
        sudo_record = self.sudo_record("/usr/sbin/reboot")
        logind_record = self.logind_record()
        sudo_record["__REALTIME_TIMESTAMP"] = sudo_record.pop(
            "_SOURCE_REALTIME_TIMESTAMP"
        )
        logind_record["__REALTIME_TIMESTAMP"] = logind_record.pop(
            "_SOURCE_REALTIME_TIMESTAMP"
        )

        evidence = self.notification.correlate_shutdown_evidence(
            [sudo_record, logind_record]
        )

        self.assertIsNotNone(evidence)
        self.assertEqual(evidence.sudo_evidence_at, "2025-10-09T08:53:20+00:00")
        self.assertEqual(evidence.shutdown_event_at, "2025-10-09T08:53:21+00:00")

    def test_missing_realtime_keeps_correlation_with_unknown_display_time(self) -> None:
        sudo_record = self.sudo_record("/usr/sbin/reboot")
        logind_record = self.logind_record()
        sudo_record.pop("_SOURCE_REALTIME_TIMESTAMP")
        logind_record.pop("_SOURCE_REALTIME_TIMESTAMP")

        evidence = self.notification.correlate_shutdown_evidence(
            [sudo_record, logind_record]
        )

        self.assertIsNotNone(evidence)
        self.assertEqual(evidence.sudo_evidence_at, "unknown")
        self.assertEqual(evidence.shutdown_event_at, "unknown")

    def test_exact_sudo_delimiter_and_user_prefix_are_required(self) -> None:
        for malformed_message in (
            "admin : TTY=x ; COMMAND =/usr/sbin/reboot",
            "admin TTY=x ; COMMAND=/usr/sbin/reboot",
            " : TTY=x ; COMMAND=/usr/sbin/reboot",
        ):
            with self.subTest(message=malformed_message):
                sudo_record = self.sudo_record("/usr/sbin/reboot")
                sudo_record["MESSAGE"] = malformed_message
                evidence = self.notification.correlate_shutdown_evidence(
                    [sudo_record, self.logind_record()]
                )
                self.assertIsNone(evidence)

    def test_shutdown_evidence_queries_current_boot_logind_and_sudo_records(
        self,
    ) -> None:
        sudo_record = self.sudo_record("/usr/sbin/reboot")
        logind_record = self.logind_record()
        with patch.object(
            self.notification,
            "journal_records",
            side_effect=([logind_record], [sudo_record]),
        ) as journal_records, patch.object(
            self.notification.time,
            "monotonic_ns",
            return_value=10_500_000_000,
        ):
            evidence = self.notification.shutdown_evidence()

        self.assertIsNotNone(evidence)
        self.assertEqual(
            journal_records.call_args_list,
            [call("systemd-logind"), call("sudo")],
        )

    def test_shutdown_evidence_rejects_stale_or_future_logind_events(self) -> None:
        for event_monotonic in (4_999_999, 10_500_001):
            with self.subTest(event_monotonic=event_monotonic), patch.object(
                self.notification,
                "journal_records",
                side_effect=(
                    [self.logind_record(monotonic=event_monotonic)],
                    [
                        self.sudo_record(
                            "/usr/sbin/reboot",
                            monotonic=event_monotonic - 1,
                        )
                    ],
                ),
            ), patch.object(
                self.notification.time,
                "monotonic_ns",
                return_value=10_000_000_000,
            ):
                evidence = self.notification.shutdown_evidence()

            self.assertIsNone(evidence)

    def test_journal_queries_are_bounded_to_the_current_boot_tail(self) -> None:
        completed = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout='{"MESSAGE": "retained"}\ninvalid-json\n',
            stderr="",
        )
        with patch.object(
            self.notification.subprocess,
            "run",
            return_value=completed,
        ) as subprocess_run:
            records = self.notification.journal_records("sudo")

        self.assertEqual(records, [{"MESSAGE": "retained"}])
        subprocess_run.assert_called_once_with(
            [
                "/usr/bin/journalctl",
                "--boot=0",
                "--identifier",
                "sudo",
                "--lines=256",
                "--no-pager",
                "--output=json",
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=self.notification.JOURNAL_TIMEOUT_SECONDS,
        )

    def test_notification_payload_marks_missing_evidence_as_unknown(self) -> None:
        payload = self.notification.notification_payload("PiServ.local", None)

        self.assertIn("Host: PiServ.local", payload)
        self.assertIn("systemd-logind shutdown event time (UTC): unknown", payload)
        self.assertIn("Nearby sudo evidence time (UTC): unknown", payload)
        self.assertIn("Nearby sudo user: unknown", payload)
        self.assertIn("Nearby sudo command: unknown", payload)

    def test_payload_normalizes_and_bounds_journal_fields(self) -> None:
        evidence = self.notification.ShutdownEvidence(
            shutdown_event_at="2025-10-09T08:53:21+00:00",
            sudo_evidence_at="2025-10-09T08:53:20+00:00",
            sudo_user="admin\nBcc: attacker@example.com",
            command=(
                "/usr/bin/systemctl reboot\r\nBcc: attacker@example.com"
                + ("x" * 600)
            ),
        )

        payload = self.notification.notification_payload("PiServ.local", evidence)

        self.assertNotIn("\nBcc:", payload)
        self.assertIn("Nearby sudo user: admin Bcc: attacker@example.com", payload)
        command_line = next(
            line for line in payload.splitlines() if line.startswith("Nearby sudo command:")
        )
        self.assertLessEqual(
            len(command_line.removeprefix("Nearby sudo command: ")),
            self.notification.FIELD_LENGTH_LIMIT,
        )

    def test_stopping_the_service_during_normal_operation_does_not_send_mail(self) -> None:
        with (
            patch.object(self.notification, "shutdown_in_progress", return_value=False),
            patch.object(self.notification.subprocess, "run") as subprocess_run,
        ):
            self.assertEqual(self.notification.main(), 0)

        subprocess_run.assert_not_called()

    def test_missing_mail_configuration_skips_shutdown_notification(self) -> None:
        with (
            patch.object(self.notification, "mail_config_available", return_value=False),
            patch.object(self.notification, "shutdown_in_progress") as shutdown_in_progress,
            patch.object(self.notification.subprocess, "run") as subprocess_run,
        ):
            self.assertEqual(self.notification.main(), 0)

        shutdown_in_progress.assert_not_called()
        subprocess_run.assert_not_called()

    def test_shutdown_in_progress_sends_correlated_evidence(self) -> None:
        evidence = self.notification.ShutdownEvidence(
            shutdown_event_at="2025-10-09T08:53:21+00:00",
            sudo_evidence_at="2025-10-09T08:53:20+00:00",
            sudo_user="admin",
            command="/usr/bin/systemctl reboot",
        )
        with (
            patch.object(self.notification, "mail_config_available", return_value=True),
            patch.object(self.notification, "shutdown_in_progress", return_value=True),
            patch.object(
                self.notification,
                "shutdown_evidence",
                return_value=evidence,
            ) as shutdown_evidence,
            patch.object(
                self.notification.socket,
                "getfqdn",
                return_value="PiServ.local",
            ),
            patch.object(self.notification.subprocess, "run") as subprocess_run,
        ):
            self.assertEqual(self.notification.main(), 0)

        shutdown_evidence.assert_called_once_with()
        subprocess_run.assert_called_once_with(
            ["/usr/sbin/sendmail", "-t"],
            input=ANY,
            text=True,
            check=True,
            timeout=self.notification.MAIL_TIMEOUT_SECONDS,
        )
        payload = subprocess_run.call_args.kwargs["input"]
        self.assertIn("Host: PiServ.local", payload)
        self.assertIn("Nearby sudo user: admin", payload)
        self.assertIn("Nearby sudo command: /usr/bin/systemctl reboot", payload)

    def test_service_template_stays_active_until_shutdown(self) -> None:
        template = render_service_template()

        self.assertIn("DefaultDependencies=no", template)
        self.assertIn("Wants=network-online.target", template)
        self.assertIn("Before=shutdown.target", template)
        self.assertIn("Conflicts=shutdown.target", template)
        self.assertIn("RemainAfterExit=yes", template)
        self.assertIn("ExecCondition=/usr/bin/test -f /etc/msmtprc", template)
        self.assertIn("ExecCondition=/usr/bin/test -s /etc/msmtprc", template)
        self.assertIn(
            "ExecStop='/opt/PiServ helpers/piserv-shutdown-notify'", template
        )
        self.assertIn("TimeoutStopSec=45s", template)
        self.assertNotIn("{{", template)

    def test_service_template_escapes_systemd_specifiers_in_condition_path(self) -> None:
        template = render_service_template("/etc/mail-%n.conf")
        self.assertIn("ConditionPathExists=/etc/mail-%%n.conf", template)
        self.assertIn("ExecCondition=/usr/bin/test -f /etc/mail-%%n.conf", template)

    def test_shutdown_notification_tasks_support_custom_paths_and_first_check_mode(
        self,
    ) -> None:
        tasks = TASKS_PATH.read_text(encoding="utf-8")

        self.assertIn("Read shutdown notification helper parent directory", tasks)
        self.assertIn("for component in path.strip(os.path.sep).split(os.path.sep)", tasks)
        self.assertIn(
            "Require trusted existing shutdown notification helper ancestors", tasks
        )
        self.assertIn("base_shutdown_notification_script_path | dirname", tasks)
        self.assertIn(
            "Require a safe existing shutdown notification helper parent directory",
            tasks,
        )
        self.assertIn(
            "Create missing shutdown notification helper parent directory", tasks
        )
        self.assertIn(
            "base_shutdown_notification_script_parent_stat.stat.exists", tasks
        )
        self.assertIn("Read shutdown notification unit state", tasks)
        self.assertIn("Read shutdown notification mail configuration state", tasks)
        self.assertIn("base_shutdown_notification_condition_stat.stat.isreg", tasks)
        self.assertIn("not ansible_check_mode", tasks)
        self.assertIn("base_shutdown_notification_unit_stat.stat.exists", tasks)


if __name__ == "__main__":
    unittest.main()
