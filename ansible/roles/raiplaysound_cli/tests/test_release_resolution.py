#!/usr/bin/env python3
"""Exercise release selection against a local mock GitHub API."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import shutil
import subprocess
import threading


class ReleaseHandler(BaseHTTPRequestHandler):
    """Serve deterministic release payloads and record requested paths."""

    def do_GET(self):
        self.server.requested_paths.append(self.path)
        responses = {
            "/latest": (200, {"tag_name": "v9.9.9"}),
            "/malformed": (200, {"tag_name": None}),
            "/empty-tag": (200, {"tag_name": ""}),
            "/missing-tag": (200, {"message": "release tag omitted"}),
        }
        status, payload = responses.get(self.path, (404, {"message": "missing"}))
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        return


def run_case(playbook, repository, variables, expected_success):
    """Run one isolated Ansible case and enforce its expected exit status."""
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
        cwd=repository,
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if (result.returncode == 0) != expected_success:
        raise AssertionError(
            "Unexpected Ansible result for release-resolution case.\n"
            f"Command: {command}\n"
            f"Exit: {result.returncode}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )


def main():
    repository = Path(__file__).resolve().parents[4]
    playbook = Path(__file__).with_name("test-release-resolution.yml")
    server = ThreadingHTTPServer(("127.0.0.1", 0), ReleaseHandler)
    server.requested_paths = []
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        api_root = f"http://127.0.0.1:{server.server_port}"
        run_case(
            playbook,
            repository,
            {
                "raiplaysound_cli_release": "latest",
                "raiplaysound_cli_latest_release_api": f"{api_root}/latest",
                "expected_tag": "v9.9.9",
            },
            expected_success=True,
        )
        if server.requested_paths != ["/latest"]:
            raise AssertionError(
                f"Latest lookup made unexpected requests: {server.requested_paths}"
            )

        run_case(
            playbook,
            repository,
            {
                "raiplaysound_cli_release": "v2.5.0",
                "raiplaysound_cli_latest_release_api": f"{api_root}/must-not-be-requested",
                "expected_tag": "v2.5.0",
            },
            expected_success=True,
        )
        if server.requested_paths != ["/latest"]:
            raise AssertionError("An explicit release tag must skip the latest API request.")

        run_case(
            playbook,
            repository,
            {
                "raiplaysound_cli_release": "",
                "raiplaysound_cli_latest_release_api": f"{api_root}/must-not-be-requested",
                "expected_failure_task": "Validate raiplaysound-cli release selector",
                "expected_failure_message": "must be 'latest' or a GitHub release tag",
            },
            expected_success=True,
        )
        if server.requested_paths != ["/latest"]:
            raise AssertionError("An empty release selector must fail before API access.")

        run_case(
            playbook,
            repository,
            {
                "raiplaysound_cli_release": "latest",
                "raiplaysound_cli_latest_release_api": f"{api_root}/malformed",
                "expected_failure_task": "Validate resolved raiplaysound-cli release tag",
                "expected_failure_message": "must be a nonempty string",
            },
            expected_success=True,
        )
        if server.requested_paths != ["/latest", "/malformed"]:
            raise AssertionError(
                "Malformed response case made unexpected requests: "
                f"{server.requested_paths}"
            )

        run_case(
            playbook,
            repository,
            {
                "raiplaysound_cli_release": "latest",
                "raiplaysound_cli_latest_release_api": f"{api_root}/empty-tag",
                "expected_failure_task": "Validate resolved raiplaysound-cli release tag",
                "expected_failure_message": "must be a nonempty string",
            },
            expected_success=True,
        )
        if server.requested_paths != ["/latest", "/malformed", "/empty-tag"]:
            raise AssertionError(
                "Empty-tag response case made unexpected requests: "
                f"{server.requested_paths}"
            )

        run_case(
            playbook,
            repository,
            {
                "raiplaysound_cli_release": "latest",
                "raiplaysound_cli_latest_release_api": f"{api_root}/missing-tag",
                "expected_failure_task": "Select raiplaysound-cli release tag",
            },
            expected_success=True,
        )
        if server.requested_paths != ["/latest", "/malformed", "/empty-tag", "/missing-tag"]:
            raise AssertionError(
                "Missing-tag response case made unexpected requests: "
                f"{server.requested_paths}"
            )

        run_case(
            playbook,
            repository,
            {
                "raiplaysound_cli_release": "latest",
                "raiplaysound_cli_latest_release_api": f"{api_root}/missing",
                "expected_failure_task": "Read latest raiplaysound-cli GitHub release",
            },
            expected_success=True,
        )
        if server.requested_paths != [
            "/latest",
            "/malformed",
            "/empty-tag",
            "/missing-tag",
            "/missing",
        ]:
            raise AssertionError(
                f"API failure case made unexpected requests: {server.requested_paths}"
            )
    finally:
        server.shutdown()
        thread.join(timeout=5)
        server.server_close()

    print(
        "Release selection cases passed: latest, explicit tag, empty selector, "
        "null/empty/missing tags, API failure."
    )


if __name__ == "__main__":
    main()
