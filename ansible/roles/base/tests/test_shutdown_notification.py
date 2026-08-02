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
from unittest.mock import patch


ROLE_DIRECTORY = Path(__file__).resolve().parent.parent
TEMPLATE_PATH = ROLE_DIRECTORY / "templates" / "piserv-shutdown-notify.py.j2"
SERVICE_TEMPLATE_PATH = ROLE_DIRECTORY / "templates" / "piserv-shutdown-notify.service.j2"


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


def render_service_template() -> str:
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
                    "        base_shutdown_notification_condition_path: /etc/msmtprc",
                    "        base_shutdown_notification_script_path: >-",
                    "          /usr/local/sbin/piserv-shutdown-notify",
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

    def test_latest_sudo_shutdown_request_uses_the_latest_matching_command(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/sbin/reboot",
            },
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000001000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl reboot",
            },
        ]

        request = self.notification.latest_sudo_shutdown_request(records)

        self.assertIsNotNone(request)
        self.assertEqual(request.requested_by, "admin")
        self.assertEqual(request.command, "/usr/bin/systemctl reboot")
        self.assertEqual(request.requested_at, "2025-10-09T08:53:21+00:00")

    def test_non_shutdown_sudo_command_is_not_reported(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/apt-get update",
            }
        ]

        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_nonoperative_shutdown_commands_are_not_reported(self) -> None:
        commands = [
            "/usr/sbin/shutdown -c now",
            "/usr/sbin/shutdown -k now",
            "/usr/sbin/reboot -w",
            "/usr/bin/systemctl --dry-run reboot",
        ]
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": str(1_760_000_000_000_000 + index),
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                f"COMMAND={command}",
            }
            for index, command in enumerate(commands)
        ]

        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_actions_for_another_manager_are_not_reported(self) -> None:
        commands = [
            "/usr/bin/systemctl --host=other reboot",
            "/usr/bin/systemctl -H other poweroff",
            "/usr/bin/systemctl --machine=container halt",
            "/usr/bin/systemctl -Mcontainer kexec",
        ]
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": str(1_760_000_000_000_000 + index),
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                f"COMMAND={command}",
            }
            for index, command in enumerate(commands)
        ]

        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_user_manager_actions_are_not_reported(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl --user reboot",
            }
        ]

        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_shutdown_cancellation_discards_earlier_scheduled_request(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/sbin/shutdown -r +10",
            },
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000001000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/sbin/shutdown -c",
            },
        ]

        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_soft_reboot_is_reported(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl soft-reboot",
            }
        ]

        request = self.notification.latest_sudo_shutdown_request(records)

        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl soft-reboot")

    def test_command_text_containing_shutdown_is_not_misclassified(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/printf shutdown",
            }
        ]

        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_lookup_of_a_shutdown_target_is_not_misclassified(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl show reboot.target",
            }
        ]

        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_isolate_of_a_shutdown_target_is_reported(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl isolate poweroff.target",
            }
        ]

        request = self.notification.latest_sudo_shutdown_request(records)

        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl isolate poweroff.target")

    def test_systemctl_start_of_a_shutdown_target_is_reported(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl start reboot.target",
            }
        ]

        request = self.notification.latest_sudo_shutdown_request(records)

        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl start reboot.target")

    def test_journal_reception_timestamp_is_used_when_source_time_is_absent(self) -> None:
        records = [
            {
                "__REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/sbin/reboot",
            },
            {
                "__REALTIME_TIMESTAMP": "1760000001000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl reboot",
            },
        ]

        request = self.notification.latest_sudo_shutdown_request(records)

        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl reboot")
        self.assertEqual(request.requested_at, "2025-10-09T08:53:21+00:00")

    def test_notification_payload_marks_missing_attribution_as_unknown(self) -> None:
        payload = self.notification.notification_payload("PiServ.local", None)

        self.assertIn("Host: PiServ.local", payload)
        self.assertIn("Shutdown request time (UTC): unknown", payload)
        self.assertIn("Requested by: unknown", payload)
        self.assertIn("Command: unknown", payload)

    def test_notification_payload_cannot_be_forged_with_journal_control_characters(
        self,
    ) -> None:
        request = self.notification.ShutdownRequest(
            requested_at="2025-10-09T08:53:21+00:00",
            requested_by="admin\nBcc: attacker@example.com",
            command="/usr/bin/systemctl reboot\r\nBcc: attacker@example.com",
        )

        payload = self.notification.notification_payload("PiServ.local", request)

        self.assertNotIn("\nBcc:", payload)
        self.assertIn("Requested by: admin Bcc: attacker@example.com", payload)
        self.assertIn(
            "Command: /usr/bin/systemctl reboot Bcc: attacker@example.com", payload
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

    def test_service_template_stays_active_until_shutdown(self) -> None:
        template = render_service_template()

        self.assertIn("DefaultDependencies=no", template)
        self.assertIn("Wants=network-online.target", template)
        self.assertIn("Before=shutdown.target", template)
        self.assertIn("Conflicts=shutdown.target", template)
        self.assertIn("RemainAfterExit=yes", template)
        self.assertIn("ExecCondition=/usr/bin/test -f /etc/msmtprc", template)
        self.assertIn("ExecCondition=/usr/bin/test -s /etc/msmtprc", template)
        self.assertIn("ExecStop=/usr/local/sbin/piserv-shutdown-notify", template)
        self.assertIn("TimeoutStopSec=45s", template)
        self.assertNotIn("{{", template)


if __name__ == "__main__":
    unittest.main()
