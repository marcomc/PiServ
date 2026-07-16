# 0015: Local Glances API Observability

## Status

Accepted and implemented on 2026-07-16.

## Context

PiServ needs low-overhead live system observability without expanding its UFW
surface. The Debian 13 `glances` package includes a systemd service, but its
default server mode runs as root. Its web UI also fails because the package
omits the static asset directory required by Glances 4.3.1.

## Decision

Use the Debian package and manage its existing `glances.service` through a
PiServ systemd drop-in.

| Area | Decision |
| --- | --- |
| Mode | Glances REST API with `--webserver --disable-webui` |
| Bind | `127.0.0.1:61208` only |
| Authentication | Existing SSH public-key authentication before local port forwarding |
| Firewall | No UFW rule; the service has no LAN or Tailscale listener |
| Privilege model | systemd `DynamicUser=yes` with private state and runtime directories |
| Package scope | `glances` and `lm-sensors`; no optional Docker, InfluxDB, SNMP, or Matplotlib integrations |

The Glances terminal UI remains available through the installed command for
interactive SSH use. A browser dashboard is intentionally out of scope until a
package version with the required static assets is available or a separately
reviewed UI is introduced.

## Consequences

Operators consume JSON API data locally or over SSH forwarding. The endpoint
has no HTTP authentication, so it must remain bound to loopback. The Ansible
role asserts both an API response and the absence of wildcard listeners on the
API port.

## Validation

On 2026-07-16, Debian `glances` version `4.3.1+dfsg-1` started under the final
dynamic-user and sandbox settings, returned API version information from
`/api/4/status`, returned CPU metrics from `/api/4/cpu`, and listened only on
`127.0.0.1:61208`. A connection to the PiServ LAN address was refused.

Starting the web UI without `--disable-webui` was also tested and failed with
`RuntimeError: Directory .../glances/outputs/static/public does not exist`.
The API-only mode avoids that Debian package defect.
