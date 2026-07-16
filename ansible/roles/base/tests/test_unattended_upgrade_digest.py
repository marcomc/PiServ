#!/usr/bin/env python3
"""Behavior tests for the PiServ unattended-upgrades mail plugin."""

from __future__ import annotations

import importlib.util
import pathlib
import unittest
from email import policy
from email.parser import BytesParser
from unittest.mock import ANY, patch


PLUGIN_PATH = pathlib.Path(__file__).parents[1] / "files" / "UnattendedUpgradesPluginPiServMail.py"


def load_plugin_module():
    spec = importlib.util.spec_from_file_location("piserv_upgrade_mail", PLUGIN_PATH)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class UnattendedUpgradeDigestTests(unittest.TestCase):
    def test_postrun_sends_mobile_digest_with_package_transitions(self) -> None:
        module = load_plugin_module()
        result = {
            "hostname": "PiServ",
            "success": True,
            "result": "All upgrades installed",
            "reboot_required": False,
            "log_dpkg": "\n".join(
                [
                    "Unpacking ntfs-3g:arm64 (1:2022.10.3-5+deb13u2) over (1:2022.10.3-5+deb13u1) ...",
                    "Unpacking helper:arm64 (2.0.0) ...",
                    "Removing obsolete-tool (1.4.0) ...",
                    "Processing triggers for libc-bin (2.41-12+rpt1+deb13u3) ...",
                ]
            ),
        }

        with patch.object(module.subprocess, "run") as sendmail:
            module.UnattendedUpgradesPluginPiServMail().postrun(result)

        sendmail.assert_called_once_with(
            [module.SENDMAIL_BINARY, "-t"], input=ANY, check=True
        )
        sent = sendmail.call_args.kwargs["input"]
        message = BytesParser(policy=policy.default).parsebytes(sent)
        plain_part = message.get_body(preferencelist=("plain",))
        html_part = message.get_body(preferencelist=("html",))

        self.assertEqual(message.get_content_type(), "multipart/alternative")
        self.assertIn("Upgrade complete", message["Subject"])
        self.assertEqual(message["To"], "root")
        self.assertIn("1:2022.10.3-5+deb13u1 -> 1:2022.10.3-5+deb13u2", plain_part.get_content())
        self.assertIn("new -> 2.0.0", plain_part.get_content())
        self.assertIn("removed: 1.4.0", plain_part.get_content())
        self.assertNotIn("Processing triggers", plain_part.get_content())
        self.assertIn("<h1>PiServ upgrade complete</h1>", html_part.get_content())
        self.assertIn("<ul>", html_part.get_content())

    def test_postrun_uses_configured_unattended_upgrades_recipient(self) -> None:
        module = load_plugin_module()

        class AptConfig:
            @staticmethod
            def find(name: str, default: str) -> str:
                self.assertEqual(name, "Unattended-Upgrade::Mail")
                self.assertEqual(default, "")
                return "alerts@example.com"

        class AptPkg:
            config = AptConfig()

        result = {
            "hostname": "PiServ",
            "success": True,
            "reboot_required": False,
            "log_dpkg": "Unpacking helper:arm64 (2.0.0) ...",
        }

        with (
            patch.object(module, "apt_pkg", AptPkg()),
            patch.object(module.subprocess, "run") as sendmail,
        ):
            module.UnattendedUpgradesPluginPiServMail().postrun(result)

        message = BytesParser(policy=policy.default).parsebytes(sendmail.call_args.kwargs["input"])
        self.assertEqual(message["To"], "alerts@example.com")

    def test_postrun_skips_when_the_mail_recipient_is_empty(self) -> None:
        module = load_plugin_module()

        class AptConfig:
            @staticmethod
            def find(name: str, default: str) -> str:
                self.assertEqual(name, "Unattended-Upgrade::Mail")
                self.assertEqual(default, "")
                return ""

        class AptPkg:
            config = AptConfig()

        result = {
            "hostname": "PiServ",
            "success": True,
            "reboot_required": False,
            "log_dpkg": "Unpacking helper:arm64 (2.0.0) ...",
        }

        with (
            patch.object(module, "apt_pkg", AptPkg()),
            patch.object(module.subprocess, "run") as sendmail,
        ):
            module.UnattendedUpgradesPluginPiServMail().postrun(result)

        sendmail.assert_not_called()

    def test_postrun_skips_no_change_successes(self) -> None:
        module = load_plugin_module()
        result = {
            "hostname": "PiServ",
            "success": True,
            "result": "No packages found that can be upgraded unattended.",
            "reboot_required": False,
            "packages_upgraded": [],
            "packages_kept_back": [],
            "packages_kept_installed": [],
            "log_dpkg": "",
        }

        with patch.object(module.subprocess, "run") as sendmail:
            module.UnattendedUpgradesPluginPiServMail().postrun(result)

        sendmail.assert_not_called()

    def test_postrun_reports_held_packages_as_action_required(self) -> None:
        module = load_plugin_module()
        result = {
            "hostname": "PiServ",
            "success": True,
            "result": "All upgrades installed",
            "reboot_required": False,
            "packages_kept_back": ["held-package"],
            "packages_kept_installed": ["kept-package"],
            "log_dpkg": "",
        }

        with patch.object(module.subprocess, "run") as sendmail:
            module.UnattendedUpgradesPluginPiServMail().postrun(result)

        sendmail.assert_called_once_with(
            [module.SENDMAIL_BINARY, "-t"], input=ANY, check=True
        )
        sent = sendmail.call_args.kwargs["input"]
        message = BytesParser(policy=policy.default).parsebytes(sent)
        plain_part = message.get_body(preferencelist=("plain",))

        self.assertIn("Upgrade requires attention", message["Subject"])
        self.assertIn("Packages requiring attention", plain_part.get_content())
        self.assertIn("kept back: held-package", plain_part.get_content())
        self.assertIn("kept installed: kept-package", plain_part.get_content())

    def test_postrun_leaves_failures_to_the_native_error_fallback(self) -> None:
        module = load_plugin_module()
        result = {
            "hostname": "PiServ",
            "success": False,
            "result": "Package configuration requires manual intervention.",
            "reboot_required": True,
            "log_dpkg": "",
        }

        with patch.object(module.subprocess, "run") as sendmail:
            module.UnattendedUpgradesPluginPiServMail().postrun(result)

        sendmail.assert_not_called()


if __name__ == "__main__":
    unittest.main()
