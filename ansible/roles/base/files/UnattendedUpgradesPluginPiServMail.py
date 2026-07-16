#!/usr/bin/env python3
"""Send a concise PiServ unattended-upgrades notification."""

from __future__ import annotations

import html
import re
import socket
import subprocess
from datetime import datetime
from email.message import EmailMessage
from typing import Any

try:
    import apt_pkg
except ImportError:  # pragma: no cover - available on unattended-upgrades hosts
    apt_pkg = None


DEFAULT_RECIPIENT = "root"
SENDMAIL_BINARY = "/usr/sbin/sendmail"
LOG_DIRECTORY = "/var/log/unattended-upgrades/"

UPGRADE_PATTERN = re.compile(
    r"^Unpacking (?P<name>\S+) \((?P<installed>[^)]+)\) over "
    r"\((?P<previous>[^)]+)\) \.\.\.$"
)
INSTALL_PATTERN = re.compile(r"^Unpacking (?P<name>\S+) \((?P<installed>[^)]+)\) \.\.\.$")
REMOVE_PATTERN = re.compile(r"^Removing (?P<name>\S+) \((?P<previous>[^)]+)\) \.\.\.$")


def package_changes(dpkg_log: str) -> list[tuple[str, str, str | None, str]]:
    """Extract user-facing package transitions from dpkg output."""
    changes: list[tuple[str, str, str | None, str]] = []
    seen_names: set[str] = set()

    for line in dpkg_log.splitlines():
        upgrade_match = UPGRADE_PATTERN.match(line)
        if upgrade_match:
            name = upgrade_match["name"]
            changes.append(("upgraded", name, upgrade_match["previous"], upgrade_match["installed"]))
            seen_names.add(name)
            continue

        install_match = INSTALL_PATTERN.match(line)
        if install_match:
            name = install_match["name"]
            if name not in seen_names:
                changes.append(("installed", name, None, install_match["installed"]))
                seen_names.add(name)
            continue

        remove_match = REMOVE_PATTERN.match(line)
        if remove_match:
            name = remove_match["name"]
            if name not in seen_names:
                changes.append(("removed", name, remove_match["previous"], ""))
                seen_names.add(name)

    return changes


def change_text(change: tuple[str, str, str | None, str]) -> str:
    """Format a package transition without implying a missing version."""
    kind, name, previous, installed = change
    if kind == "upgraded":
        return f"{name}  {previous} -> {installed}"
    if kind == "installed":
        return f"{name}  new -> {installed}"
    return f"{name}  removed: {previous}"


def attention_items(result: dict[str, Any]) -> list[str]:
    """Return packages held back from an otherwise successful run."""
    items = [f"kept back: {package}" for package in result.get("packages_kept_back", [])]
    items.extend(
        f"kept installed: {package}" for package in result.get("packages_kept_installed", [])
    )
    return items


def mail_recipient() -> str:
    """Read the configured unattended-upgrades recipient."""
    if apt_pkg is None:
        return DEFAULT_RECIPIENT
    return str(apt_pkg.config.find("Unattended-Upgrade::Mail", ""))


def should_send_digest(result: dict[str, Any], recipient: str) -> bool:
    """Send only successful changes or successful runs needing attention."""
    if not recipient or not bool(result.get("success")):
        return False
    changes = package_changes(str(result.get("log_dpkg") or ""))
    return bool(changes or attention_items(result))


def build_message(result: dict[str, Any], recipient: str) -> EmailMessage:
    """Build an accessible multipart message from the plugin result."""
    success = bool(result.get("success"))
    hostname = str(result.get("hostname") or socket.getfqdn() or socket.gethostname())
    reboot_required = bool(result.get("reboot_required"))
    changes = package_changes(str(result.get("log_dpkg") or ""))
    attention = attention_items(result)
    status = "Upgrade complete" if success and not attention else "Upgrade requires attention"
    reboot_status = "required" if reboot_required else "not required"
    timestamp = datetime.now().astimezone().strftime("%d %b %Y, %H:%M %Z")
    subject = f"[PiServ] {status}: {len(changes)} packages; reboot {reboot_status}"

    lines = [
        f"{hostname} {status.lower()}",
        timestamp,
        "",
        "At a glance",
        f"- Status: {'completed' if success and not attention else 'requires attention'}",
        f"- Packages changed: {len(changes)}",
        f"- Reboot: {reboot_status}",
    ]
    lines.extend(["", "Changed packages"])
    if changes:
        lines.extend(f"- {change_text(change)}" for change in changes)
    else:
        lines.append("- No package transitions were recorded.")
    if attention:
        lines.extend(["", "Packages requiring attention"])
        lines.extend(f"- {item}" for item in attention)
    lines.extend(["", "Technical detail", f"Full log retained on PiServ: {LOG_DIRECTORY}", ""])
    plain_text = "\n".join(lines)

    change_items = "".join(f"<li>{html.escape(change_text(change))}</li>" for change in changes)
    if not change_items:
        change_items = "<li>No package transitions were recorded.</li>"
    attention_items_html = "".join(f"<li>{html.escape(item)}</li>" for item in attention)
    attention_section = ""
    if attention_items_html:
        attention_section = f"<h2>Packages requiring attention</h2><ul>{attention_items_html}</ul>"
    html_body = f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body {{ background: #ffffff; color: #202124; font-family: Arial, sans-serif; line-height: 1.5; margin: 0; }}
      main {{ margin: 0 auto; max-width: 600px; padding: 20px; }}
      h1 {{ font-size: 24px; margin: 0 0 8px; }}
      h2 {{ font-size: 18px; margin: 24px 0 8px; }}
      dl {{ margin: 0; }}
      dt {{ font-weight: bold; }}
      dd {{ margin: 0 0 8px; }}
      li {{ overflow-wrap: anywhere; }}
      .muted {{ color: #5f6368; }}
    </style>
  </head>
  <body>
    <main>
      <h1>{html.escape(hostname)} {html.escape(status.lower())}</h1>
      <p class="muted">{html.escape(timestamp)}</p>
      <h2>At a glance</h2>
      <dl>
        <dt>Status</dt><dd>{'completed' if success and not attention else 'requires attention'}</dd>
        <dt>Packages changed</dt><dd>{len(changes)}</dd>
        <dt>Reboot</dt><dd>{html.escape(reboot_status)}</dd>
      </dl>
      <h2>Changed packages</h2>
      <ul>{change_items}</ul>
      {attention_section}
      <h2>Technical detail</h2>
      <p>Full log retained on PiServ: <code>{LOG_DIRECTORY}</code></p>
    </main>
  </body>
</html>
"""

    message = EmailMessage()
    message["To"] = recipient
    message["Subject"] = subject
    message.set_content(plain_text)
    message.add_alternative(html_body, subtype="html")
    return message


class UnattendedUpgradesPluginPiServMail:
    """Deliver concise post-run mail without changing upgrade behavior."""

    def postrun(self, result: dict[str, Any]) -> None:
        recipient = mail_recipient()
        if not should_send_digest(result, recipient):
            return
        message = build_message(result, recipient)
        subprocess.run([SENDMAIL_BINARY, "-t"], input=message.as_bytes(), check=True)
