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
        cls._latest_sudo_shutdown_request = (
            cls.notification.latest_sudo_shutdown_request
        )

        def latest_sudo_shutdown_request(records: list[dict[str, object]]) -> object:
            for record in records:
                record.setdefault("_COMM", "sudo")
                record.setdefault("_EXE", "/usr/bin/sudo")
                record.setdefault("_UID", "0")
            return cls._latest_sudo_shutdown_request(records)

        cls.notification.latest_sudo_shutdown_request = latest_sudo_shutdown_request

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
            "/usr/bin/systemctl -h reboot",
            "/usr/bin/systemctl -qh reboot",
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

    def test_abbreviated_nonoperative_direct_commands_are_not_reported(self) -> None:
        commands = ["/usr/sbin/shutdown --sho", "/usr/sbin/reboot --wtmp"]
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": str(1_760_000_000_000_000 + index),
                "MESSAGE": "admin : TTY=x ; COMMAND=" + command,
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

    def test_abbreviated_systemctl_manager_selectors_are_not_reported(self) -> None:
        commands = [
            "/usr/bin/systemctl --hos=other reboot",
            "/usr/bin/systemctl --mach=container poweroff",
        ]
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": str(1_760_000_000_000_000 + index),
                "MESSAGE": "admin : TTY=x ; COMMAND=" + command,
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

    def test_abbreviated_systemctl_user_manager_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --us reboot"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_offline_root_and_image_actions_are_not_reported(self) -> None:
        commands = [
            "/usr/bin/systemctl --root=/tmp reboot",
            "/usr/bin/systemctl --image=/tmp/root.img poweroff",
        ]
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": str(1_760_000_000_000_000 + index),
                "MESSAGE": "admin : TTY=x ; COMMAND=" + command,
            }
            for index, command in enumerate(commands)
        ]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_forged_sudo_identifier_record_is_not_reported(self) -> None:
        records = [{"_COMM": "logger", "_EXE": "/usr/bin/logger", "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "victim : TTY=x ; COMMAND=/usr/bin/systemctl reboot"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_sudo_command_delimiter_ignores_command_text_in_the_working_directory(
        self,
    ) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; PWD=/tmp/COMMAND=notes ; COMMAND=/usr/bin/systemctl reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl reboot")

    def test_untrusted_shutdown_executable_path_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/tmp/reboot"}]
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

    def test_shutdown_end_of_options_marker_preserves_wall_message_text(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/sbin/shutdown -- +5 -c"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/sbin/shutdown -- +5 -c")

    def test_systemctl_when_cancel_discards_earlier_scheduled_request(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl reboot --when=5m",
            },
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000001000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl reboot --when=cancel",
            },
        ]

        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_when_show_is_not_reported(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl reboot --when=show",
            }
        ]

        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_abbreviated_systemctl_when_show_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --whe show reboot"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_dash_prefixed_verb_after_end_of_options_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl -- -h reboot"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_split_when_value_preserves_shutdown_action(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl --when 5m reboot",
            }
        ]

        request = self.notification.latest_sudo_shutdown_request(records)

        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl --when 5m reboot")

    def test_systemctl_split_check_inhibitors_value_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --check-inhibitors no reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl --check-inhibitors no reboot")

    def test_systemctl_split_output_value_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --output short reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl --output short reboot")

    def test_systemctl_split_legend_value_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --legend no reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl --legend no reboot")

    def test_systemctl_shutdown_action_with_extra_operand_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl reboot extra"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_direct_halt_and_poweroff_with_operands_are_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/sbin/halt extra"}, {"_SOURCE_REALTIME_TIMESTAMP": "1760000000000001", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/sbin/poweroff extra"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_direct_commands_reject_operands_after_the_option_marker(self) -> None:
        commands = [
            "/usr/sbin/halt -- -w",
            "/usr/sbin/reboot -- -w extra",
        ]
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": str(1_760_000_000_000_000 + index),
                "MESSAGE": "admin : TTY=x ; COMMAND=" + command,
            }
            for index, command in enumerate(commands)
        ]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_isolate_with_extra_operand_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl isolate reboot.target extra"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_abbreviated_split_output_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --out short reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl --out short reboot")

    def test_ambiguous_systemctl_when_prefix_does_not_cancel_a_request(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=x ; COMMAND=/usr/sbin/shutdown -r +10",
            },
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000001",
                "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --w cancel reboot",
            },
        ]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/sbin/shutdown -r +10")

    def test_systemctl_ambiguous_attached_option_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --bo=foo reboot"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_unknown_systemctl_option_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --definitely-invalid reboot"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_unknown_direct_command_option_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/sbin/reboot --definitely-invalid"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_no_wall_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --no-wall reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl --no-wall reboot")

    def test_invalid_shutdown_cancellation_does_not_clear_a_request(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=x ; COMMAND=/usr/sbin/shutdown -r +10",
            },
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000001",
                "MESSAGE": "admin : TTY=x ; COMMAND=/usr/sbin/shutdown --definitely-invalid -c",
            },
        ]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/sbin/shutdown -r +10")

    def test_unsupported_shutdown_options_are_not_reported(self) -> None:
        commands = [
            "/usr/sbin/shutdown --force now",
            "/usr/sbin/shutdown --no-sync now",
            "/usr/sbin/shutdown --verbose now",
        ]
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": str(1_760_000_000_000_000 + index),
                "MESSAGE": "admin : TTY=x ; COMMAND=" + command,
            }
            for index, command in enumerate(commands)
        ]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_split_boot_loader_entry_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --boot-loader-entry recovery reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl --boot-loader-entry recovery reboot")

    def test_systemctl_split_kill_value_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --kill-value 9 reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl --kill-value 9 reboot")

    def test_systemctl_inhibitor_shortcut_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl -i reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl -i reboot")

    def test_systemctl_property_value_does_not_select_user_manager(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl -p --user reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl -p --user reboot")

    def test_systemctl_firmware_setup_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --firmware-setup reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl --firmware-setup reboot")

    def test_systemctl_system_manager_selector_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --system reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl --system reboot")

    def test_direct_no_wtmp_and_clustered_options_preserve_shutdown_actions(self) -> None:
        commands = [
            "/usr/sbin/reboot -d",
            "/usr/sbin/shutdown -rh now",
            "/usr/sbin/reboot -fp",
        ]
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": str(1_760_000_000_000_000 + index),
                "MESSAGE": "admin : TTY=x ; COMMAND=" + command,
            }
            for index, command in enumerate(commands)
        ]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/sbin/reboot -fp")

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

    def test_systemctl_start_of_multiple_units_reports_a_shutdown_target(self) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/bin/systemctl start auxiliary.service reboot.target",
            }
        ]

        request = self.notification.latest_sudo_shutdown_request(records)

        self.assertIsNotNone(request)
        self.assertEqual(
            request.command,
            "/usr/bin/systemctl start auxiliary.service reboot.target",
        )

    def test_systemctl_soft_reboot_target_is_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl isolate soft-reboot.target"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl isolate soft-reboot.target")

    def test_systemctl_shutdown_target_alias_is_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl isolate runlevel6.target"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl isolate runlevel6.target")

    def test_systemctl_restart_of_a_shutdown_target_is_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl restart reboot.target"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl restart reboot.target")

    def test_systemctl_reload_or_restart_of_a_shutdown_target_is_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl reload-or-restart reboot.target"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl reload-or-restart reboot.target")

    def test_systemctl_force_reload_of_a_shutdown_target_is_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl force-reload reboot.target"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl force-reload reboot.target")

    def test_long_dry_run_command_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl reboot --message=" + ("x" * 600) + " --dry-run"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_abbreviated_systemctl_dry_run_is_not_reported(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl --dry reboot"}]
        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

    def test_systemctl_end_of_options_marker_preserves_shutdown_action(self) -> None:
        records = [{"_SOURCE_REALTIME_TIMESTAMP": "1760000000000000", "MESSAGE": "admin : TTY=x ; COMMAND=/usr/bin/systemctl -- reboot"}]
        request = self.notification.latest_sudo_shutdown_request(records)
        self.assertIsNotNone(request)
        self.assertEqual(request.command, "/usr/bin/systemctl -- reboot")

    def test_monotonic_journal_time_orders_a_cancellation_after_clock_correction(
        self,
    ) -> None:
        records = [
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000001000000",
                "__MONOTONIC_TIMESTAMP": "100",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/sbin/shutdown -r +10",
            },
            {
                "_SOURCE_REALTIME_TIMESTAMP": "1760000000000000",
                "__MONOTONIC_TIMESTAMP": "200",
                "MESSAGE": "admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; "
                "COMMAND=/usr/sbin/shutdown -c",
            },
        ]

        self.assertIsNone(self.notification.latest_sudo_shutdown_request(records))

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
        self.assertIn("Require trusted existing shutdown notification helper ancestors", tasks)
        self.assertIn("base_shutdown_notification_script_path | dirname", tasks)
        self.assertIn(
            "Require a safe existing shutdown notification helper parent directory",
            tasks,
        )
        self.assertIn("Create missing shutdown notification helper parent directory", tasks)
        self.assertIn("base_shutdown_notification_script_parent_stat.stat.exists", tasks)
        self.assertIn("Read shutdown notification unit state", tasks)
        self.assertIn("Read shutdown notification mail configuration state", tasks)
        self.assertIn("base_shutdown_notification_condition_stat.stat.isreg", tasks)
        self.assertIn("not ansible_check_mode", tasks)
        self.assertIn("base_shutdown_notification_unit_stat.stat.exists", tasks)


if __name__ == "__main__":
    unittest.main()
