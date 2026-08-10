"""Regression tests for Home Assistant CLI playbook orchestration."""

import subprocess
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
PLAYBOOKS = REPO_ROOT / "ansible" / "playbooks"


def load_yaml(path: Path) -> list[dict]:
    """Load one playbook as a list of plays or import entries."""
    with path.open(encoding="utf-8") as stream:
        return yaml.safe_load(stream)


class HomeAssistantCliOrchestrationTests(unittest.TestCase):
    """Verify disabled and enabled orchestration contracts."""

    def test_full_install_does_not_repeat_cli_after_hermes(self) -> None:
        entries = load_yaml(PLAYBOOKS / "piserv-install.yml")
        imports = [entry.get("import_playbook") for entry in entries]
        self.assertNotIn("homeassistant-cli.yml", imports)

    def test_standalone_hermes_installs_cli_before_main_role(self) -> None:
        (play,) = load_yaml(PLAYBOOKS / "hermes-agent.yml")
        task_names = [task["name"] for task in play["pre_tasks"]]
        cli_index = task_names.index(
            "Install Home Assistant CLI for the Hermes terminal"
        )
        self.assertLess(
            task_names.index(
                "Establish the Hermes runtime identity before project CLI setup"
            ),
            cli_index,
        )
        self.assertEqual(play["roles"][0]["role"], "hermes_agent")

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
