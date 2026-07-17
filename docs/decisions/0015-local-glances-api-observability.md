# 0015: LAN Glances API Observability

## Status

Accepted and implemented on 2026-07-16.

## Context

PiServ needs system metrics available to LAN operators and Home Assistant. The
native Home Assistant Glances integration polls the Glances API in Web Server
Mode. The initial loopback-only API could not satisfy that integration.

PiGuard uses Glances with the same IPv4-wildcard, API-only pattern for its
primary and secondary servers. The Debian 13 `glances` package includes a
systemd service, but its default server mode runs as root. Its web UI also fails
because the package omits the static asset directory required by Glances 4.3.1.

## Decision

Use the Debian package and manage its existing `glances.service` through a
PiServ systemd drop-in. Bind the API to IPv4 with the web UI disabled, and use
UFW to accept TCP `61208` from the current IPv4 LAN CIDR.

| Area | Decision |
| --- | --- |
| Mode | Glances REST API with `--webserver --disable-webui` |
| Bind | IPv4 wildcard on TCP `61208`; no IPv6 listener |
| Consumers | IPv4 LAN clients, including Home Assistant |
| Authentication | No HTTP credentials; trusted LAN and tailnet ACLs are access boundaries |
| Firewall | Allow TCP `61208` from the current IPv4 LAN CIDR; existing Tailscale ingress applies |
| Privilege model | systemd `DynamicUser=yes` with private state and runtime directories |
| Package scope | `glances`, `lm-sensors`, and required `python3-uvicorn`; no optional Docker, InfluxDB, SNMP, or Matplotlib integrations |

The Glances terminal UI remains available through SSH. The browser web UI is
intentionally out of scope until a package version includes its required static
assets.

## Consequences

The API is unauthenticated HTTP and is visible to all clients on the trusted
IPv4 LAN and authenticated tailnet identities allowed by Tailnet ACLs. IPv6 LAN
ingress stays blocked. The role asserts a local API response, the configured
IPv4 listener, and no IPv6 wildcard listener.

## Validation

On 2026-07-16, Debian `glances` version `4.3.1+dfsg-1` returned API version
information from `/api/4/status` and CPU metrics from `/api/4/cpu`.

Starting the web UI without `--disable-webui` was also tested and failed with
`RuntimeError: Directory .../glances/outputs/static/public does not exist`.
The API-only mode avoids that Debian package defect.
