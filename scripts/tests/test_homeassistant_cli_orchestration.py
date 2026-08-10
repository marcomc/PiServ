"""Regression tests for Home Assistant CLI playbook orchestration."""

import subprocess
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
PLAYBOOKS = REPO_ROOT / "ansible" / "playbooks"
MANAGE_EXPRESSION = (
    "piserv_hermes_agent_manage_home_assistant_mcp | default(false) | bool"
)


def load_yaml(path: Path) -> list[dict]:
    """Load one playbook as a list of plays or import entries."""
    with path.open(encoding="utf-8") as stream:
        return yaml.safe_load(stream)


class HomeAssistantCliOrchestrationTests(unittest.TestCase):
    """Verify disabled and enabled orchestration contracts."""

    def test_full_install_gates_cli_import_when_mcp_is_disabled(self) -> None:
        entries = load_yaml(PLAYBOOKS / "piserv-install.yml")
        cli_import = next(
            entry
            for entry in entries
            if entry.get("import_playbook") == "homeassistant-cli.yml"
        )

        self.assertEqual(cli_import.get("when"), MANAGE_EXPRESSION)

    def run_standalone(self, enabled: bool) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "ansible-playbook",
                "--inventory",
                "piserv,",
                "--connection",
                "local",
                "--check",
                "--extra-vars",
                f"piserv_hermes_agent_manage_home_assistant_mcp={str(enabled).lower()}",
                "--extra-vars",
                "homeassistant_cli_server=",
                str(PLAYBOOKS / "homeassistant-cli.yml"),
            ],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_standalone_playbook_gates_role_at_runtime(self) -> None:
        (play,) = load_yaml(PLAYBOOKS / "homeassistant-cli.yml")
        self.assertEqual(play["roles"][0].get("role"), "homeassistant_cli")
        self.assertEqual(
            play["roles"][0].get("when"),
            "piserv_hermes_agent_manage_home_assistant_mcp | bool",
        )

        disabled = self.run_standalone(False)
        self.assertEqual(disabled.returncode, 0, disabled.stdout + disabled.stderr)
        self.assertRegex(
            disabled.stdout,
            r"Validate Home Assistant CLI inputs[^\n]*\n+skipping: \[piserv\]",
        )

        enabled = self.run_standalone(True)
        self.assertNotEqual(enabled.returncode, 0)
        self.assertIn("Validate Home Assistant CLI inputs", enabled.stdout)
        self.assertIn("Home Assistant CLI requires a runtime identity", enabled.stdout)


if __name__ == "__main__":
    unittest.main()
