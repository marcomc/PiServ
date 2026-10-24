#!/usr/bin/env python3
"""Verify release changes install once and converged runs skip installation."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import getpass
import json
import shutil
import subprocess
import tempfile
import threading


class LatestReleaseHandler(BaseHTTPRequestHandler):
    """Serve the current synthetic latest tag and record API requests."""

    def do_GET(self):
        self.server.requested_paths.append(self.path)
        if self.path != "/latest":
            self.send_error(404)
            return
        body = json.dumps({"tag_name": self.server.latest_tag}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        return


def run_git(repository, *arguments):
    result = subprocess.run(
        ["git", "-C", str(repository), *arguments],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.stdout.strip()


def commit_release(repository, version):
    (repository / "VERSION").write_text(f"{version}\n")
    run_git(repository, "add", "VERSION")
    run_git(repository, "commit", "-m", f"Release {version}")
    run_git(repository, "tag", version)


def run_install(playbook, repository_root, variables):
    command = [
        shutil.which("ansible-playbook") or "ansible-playbook",
        "--inventory",
        "localhost,",
        "--extra-vars",
        json.dumps(variables),
        str(playbook),
    ]
    result = subprocess.run(
        command,
        cwd=repository_root,
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.returncode:
        raise AssertionError(
            "Ansible checkout/install transition failed.\n"
            f"Command: {command}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )


def main():
    repository_root = Path(__file__).resolve().parents[4]
    playbook = Path(__file__).with_name("test-install-transition.yml")
    with tempfile.TemporaryDirectory(prefix="raiplaysound-release-test-") as temp_root:
        temp = Path(temp_root)
        upstream = temp / "upstream"
        checkout = temp / "checkout"
        runtime_home = temp / "runtime-home"
        upstream.mkdir()
        runtime_home.mkdir()
        run_git(upstream, "init", "--quiet")
        run_git(upstream, "config", "user.name", "RaiPlaySound test")
        run_git(upstream, "config", "user.email", "test@example.com")
        (upstream / "Makefile").write_text(
            "install:\n"
            "\tmkdir -p \"$(HOME)/.local/bin\" \"$(HOME)/.local/state\"\n"
            "\tcp VERSION \"$(HOME)/.local/bin/raiplaysound-cli\"\n"
            "\techo install >> \"$(HOME)/.local/state/install-count\"\n"
        )
        run_git(upstream, "add", "Makefile")
        commit_release(upstream, "v1.0.0")

        server = ThreadingHTTPServer(("127.0.0.1", 0), LatestReleaseHandler)
        server.latest_tag = "v1.0.0"
        server.requested_paths = []
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            common = {
                "ansible_become": False,
                "raiplaysound_cli_runtime_user": getpass.getuser(),
                "raiplaysound_cli_runtime_user_home": str(runtime_home),
                "raiplaysound_cli_repo_url": str(upstream),
                "raiplaysound_cli_repo_update": True,
                "raiplaysound_cli_repo_force": False,
                "raiplaysound_cli_force_install": False,
                "raiplaysound_cli_source_dir": str(checkout),
                "raiplaysound_cli_release": "latest",
                "raiplaysound_cli_latest_release_api": (
                    f"http://127.0.0.1:{server.server_port}/latest"
                ),
            }

            run_install(
                playbook,
                repository_root,
                {**common, "expected_tag": "v1.0.0"},
            )
            installed = runtime_home / ".local/bin/raiplaysound-cli"
            install_count = runtime_home / ".local/state/install-count"
            if installed.read_text().strip() != "v1.0.0":
                raise AssertionError("Initial latest tag was not installed.")
            if len(install_count.read_text().splitlines()) != 1:
                raise AssertionError("Initial checkout did not install exactly once.")

            run_install(
                playbook,
                repository_root,
                {**common, "expected_tag": "v1.0.0"},
            )
            if len(install_count.read_text().splitlines()) != 1:
                raise AssertionError("A converged run repeated make install.")

            commit_release(upstream, "v1.1.0")
            server.latest_tag = "v1.1.0"
            run_install(
                playbook,
                repository_root,
                {**common, "expected_tag": "v1.1.0"},
            )
            if installed.read_text().strip() != "v1.1.0":
                raise AssertionError("A new latest tag was not installed.")
            if len(install_count.read_text().splitlines()) != 2:
                raise AssertionError("A new checkout did not trigger make install.")

            api_requests = list(server.requested_paths)
            explicit = {
                **common,
                "raiplaysound_cli_release": "v1.0.0",
                "raiplaysound_cli_latest_release_api": (
                    f"http://127.0.0.1:{server.server_port}/must-not-be-requested"
                ),
                "expected_tag": "v1.0.0",
            }
            run_install(playbook, repository_root, explicit)
            if server.requested_paths != api_requests:
                raise AssertionError("An explicit tag triggered a latest API request.")
            if installed.read_text().strip() != "v1.0.0":
                raise AssertionError("An explicit release tag was not installed.")
            if len(install_count.read_text().splitlines()) != 3:
                raise AssertionError("Changing to an explicit tag did not reinstall.")

            run_install(playbook, repository_root, explicit)
            if len(install_count.read_text().splitlines()) != 3:
                raise AssertionError("A converged explicit-tag run repeated installation.")
        finally:
            server.shutdown()
            thread.join(timeout=5)
            server.server_close()

    print("Checkout/install transitions passed: latest upgrade, explicit tag, convergence.")


if __name__ == "__main__":
    main()
