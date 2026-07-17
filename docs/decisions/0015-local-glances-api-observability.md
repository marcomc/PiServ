# 0015: LAN Glances API Observability

## Status

Accepted and implemented on 2026-07-16.

The direct API exposure residual risk was explicitly accepted on 2026-07-17.

## Context

PiServ needs system metrics available to LAN operators and Home Assistant. The
native Home Assistant Glances integration polls the Glances API in Web Server
Mode. The initial loopback-only API could not satisfy that integration.

PiGuard uses Glances with the same IPv4-wildcard, API-only pattern for its
primary and secondary servers. The Debian 13 `glances` package includes a
systemd service, but its default server mode runs as root. Its web UI also fails
because the package omits the static asset directory required by Glances 4.3.1.

## Risk Acceptance

PiServ deliberately publishes the HTTP Basic-authenticated Glances API directly
to the current trusted IPv4 LAN and to Tailnet identities permitted by ACLs. The
host relies on UFW for LAN scope, Tailnet ACLs for Tailnet scope, and unattended
security upgrades when Debian publishes the relevant package fixes. It does not
publish the API to untrusted networks or IPv6 LAN clients.

This is an accepted residual risk for local observability. Reassess the decision
if PiServ is exposed to a less-trusted network, if the API needs internet access,
or if an upstream security fix remains unavailable for an extended period.

## Decision

Use the Debian package and manage its existing `glances.service` through a
PiServ systemd drop-in. Bind the API to IPv4 with the web UI disabled, and use
UFW to accept TCP `61208` from the current IPv4 LAN CIDR.

| Area | Decision |
| --- | --- |
| Mode | Glances REST API with `--webserver --disable-webui` |
| Bind | IPv4 wildcard on TCP `61208`; no IPv6 listener |
| Consumers | IPv4 LAN clients, including Home Assistant |
| Authentication | HTTP Basic authentication using a salted host-local password hash |
| Firewall | Allow TCP `61208` from the current IPv4 LAN CIDR; existing Tailscale ingress applies |
| Privilege model | systemd `DynamicUser=yes` with private state and runtime directories |
| Package scope | `glances`, `lm-sensors`, `python3-uvicorn`, and `python3-jinja2`; no optional Docker, InfluxDB, SNMP, or Matplotlib integrations |

The Glances terminal UI remains available through SSH. The browser web UI is
intentionally out of scope until a package version includes its required static
assets.

## Consequences

The API is reachable from the IPv4 LAN and, because UFW allows all ingress on
`tailscale0`, from tailnet identities permitted by the tailnet ACLs. Both paths
require the same HTTP Basic credentials. IPv6 LAN ingress stays blocked. The
role creates a random bootstrap password only when no password hash exists; the
plaintext is root-readable at first deployment and can be removed after Home
Assistant is configured, while the salted hash remains service-readable. The
role asserts anonymous `401`, authenticated local access while the bootstrap
exists, the configured IPv4 listener, and no IPv6 wildcard listener.

## Validation

On 2026-07-16, Debian `glances` version `4.3.1+dfsg-1` returned API version
information from `/api/4/status` and CPU metrics from `/api/4/cpu`.

Starting the web UI without `--disable-webui` was also tested and failed with
`RuntimeError: Directory .../glances/outputs/static/public does not exist`.
The API-only mode avoids that Debian package defect.
