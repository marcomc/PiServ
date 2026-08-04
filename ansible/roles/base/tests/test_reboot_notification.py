#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import py_compile
import subprocess
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest.mock import call, patch


ROLE_DIRECTORY = Path(__file__).resolve().parent.parent
TEMPLATE_PATH = ROLE_DIRECTORY / "templates" / "piserv-reboot-notify.py.j2"
SERVICE_TEMPLATE_PATH = ROLE_DIRECTORY / "templates" / "piserv-reboot-notify.service.j2"


def load_notification_module() -> object:
    template = TEMPLATE_PATH.read_text(encoding="utf-8")
    rendered = (
        template.replace(
            "{{ base_reboot_notification_recipient | to_json }}", '"root"'
        )
        .replace(
            "{{ base_reboot_notification_subject_prefix | to_json }}", '"[PiServ]"'
        )
        .replace("{{ base_reboot_notification_retry_attempts | to_json }}", "6")
        .replace(
            "{{ base_reboot_notification_retry_delay_seconds | to_json }}", "15"
        )
        .replace(
            "{{ base_reboot_notification_delivery_timeout_seconds | to_json }}",
            "20",
        )
    )
    with tempfile.TemporaryDirectory() as temporary_directory:
        script_path = Path(temporary_directory) / "piserv-reboot-notify"
        script_path.write_text(rendered, encoding="utf-8")
        py_compile.compile(str(script_path), doraise=True)
        loader = SourceFileLoader("piserv_reboot_notify", str(script_path))
        specification = importlib.util.spec_from_loader("piserv_reboot_notify", loader)
        if specification is None or specification.loader is None:
            raise RuntimeError("could not load the rendered reboot notification helper")
        module = importlib.util.module_from_spec(specification)
        sys.modules[specification.name] = module
        specification.loader.exec_module(module)
        return module


class RebootNotificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.notification = load_notification_module()

    def test_temporary_failure_retries_then_succeeds(self) -> None:
        temporary_failure = subprocess.CalledProcessError(
            75, ["/usr/sbin/sendmail", "-t"]
        )

        with (
            patch.object(
                self.notification,
                "subprocess",
            ) as subprocess_module,
            patch.object(self.notification.time, "sleep") as sleep,
        ):
            subprocess_module.CalledProcessError = subprocess.CalledProcessError
            subprocess_module.run.side_effect = [temporary_failure, None]

            self.notification.deliver("payload")

        expected_call = call(
            ["/usr/sbin/sendmail", "-t"],
            input="payload",
            text=True,
            check=True,
            timeout=20,
        )
        self.assertEqual(subprocess_module.run.call_args_list, [expected_call] * 2)
        sleep.assert_called_once_with(15)

    def test_service_timeout_covers_retry_budget(self) -> None:
        service_template = SERVICE_TEMPLATE_PATH.read_text(encoding="utf-8")

        self.assertIn("TimeoutStartSec=", service_template)
        self.assertIn("base_reboot_notification_retry_attempts", service_template)
        self.assertIn(
            "base_reboot_notification_delivery_timeout_seconds", service_template
        )
        self.assertIn(
            "base_reboot_notification_retry_delay_seconds", service_template
        )

    def test_permanent_failure_is_not_retried(self) -> None:
        permanent_failure = subprocess.CalledProcessError(
            77, ["/usr/sbin/sendmail", "-t"]
        )

        with (
            patch.object(
                self.notification,
                "subprocess",
            ) as subprocess_module,
            patch.object(self.notification.time, "sleep") as sleep,
        ):
            subprocess_module.CalledProcessError = subprocess.CalledProcessError
            subprocess_module.run.side_effect = permanent_failure

            with self.assertRaises(subprocess.CalledProcessError):
                self.notification.deliver("payload")

        self.assertEqual(subprocess_module.run.call_count, 1)
        sleep.assert_not_called()

    def test_delivery_timeout_is_not_retried(self) -> None:
        timeout_failure = subprocess.TimeoutExpired(
            ["/usr/sbin/sendmail", "-t"], 20
        )

        with (
            patch.object(
                self.notification,
                "subprocess",
            ) as subprocess_module,
            patch.object(self.notification.time, "sleep") as sleep,
        ):
            subprocess_module.CalledProcessError = subprocess.CalledProcessError
            subprocess_module.TimeoutExpired = subprocess.TimeoutExpired
            subprocess_module.run.side_effect = timeout_failure

            with self.assertRaises(subprocess.TimeoutExpired):
                self.notification.deliver("payload")

        self.assertEqual(subprocess_module.run.call_count, 1)
        sleep.assert_not_called()

    def test_temporary_failure_stays_visible_after_retry_budget(self) -> None:
        temporary_failure = subprocess.CalledProcessError(
            75, ["/usr/sbin/sendmail", "-t"]
        )

        with (
            patch.object(
                self.notification,
                "subprocess",
            ) as subprocess_module,
            patch.object(self.notification.time, "sleep") as sleep,
        ):
            subprocess_module.CalledProcessError = subprocess.CalledProcessError
            subprocess_module.run.side_effect = [temporary_failure] * 6

            with self.assertRaises(subprocess.CalledProcessError):
                self.notification.deliver("payload")

        self.assertEqual(subprocess_module.run.call_count, 6)
        self.assertEqual(sleep.call_args_list, [call(15)] * 5)


if __name__ == "__main__":
    unittest.main()
