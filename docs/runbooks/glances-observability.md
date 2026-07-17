# Glances Observability

## Table of Contents

- [Purpose](#purpose)
- [Apply](#apply)
- [LAN and Home Assistant Access](#lan-and-home-assistant-access)
- [Local Access](#local-access)
- [Validation](#validation)
- [Recovery](#recovery)

## Purpose

Operate PiServ's Glances JSON API for LAN observability and Home Assistant
system monitoring. The Debian 13 web UI remains disabled because its static
assets are unavailable.

## Apply

```sh
ansible-playbook ansible/playbooks/piserv-base.yml
ansible-playbook ansible/playbooks/firewall.yml
```

The base role installs `glances` and `lm-sensors` without optional integrations,
then starts the Debian `glances.service` in API-only mode on IPv4 port `61208`.
UFW permits the port from PiServ's current IPv4 LAN CIDR. The existing
`tailscale0` policy also permits authenticated tailnet clients according to
tailnet ACLs.

## LAN and Home Assistant Access

Query the API from any IPv4 LAN client:

```sh
curl -fsS http://PiServ.local:61208/api/4/status
curl -fsS http://PiServ.local:61208/api/4/cpu
```

In Home Assistant, add the **Glances** integration from **Settings > Devices &
services**. Use `PiServ.local` as the host and `61208` as the port. If the host
resolver attempts IPv6 first, use PiServ's current IPv4 address instead because
the API intentionally has no IPv6 listener.

The API is unauthenticated HTTP. The current IPv4 LAN and tailnet ACLs are its
access boundaries. Do not expose TCP `61208` to other networks without a
separate authentication and firewall decision.

## Local Access

Query the local API on PiServ:

```sh
curl -fsS http://127.0.0.1:61208/api/4/status
curl -fsS http://127.0.0.1:61208/api/4/cpu
```

For an interactive terminal view, connect through SSH and run:

```sh
glances
```

## Validation

The 2026-07-16 deployment confirmed Glances `4.3.1+dfsg-1` as active and the
local API as responsive. PiGuard uses the same API-only IPv4-wildcard pattern
for its primary and secondary servers.

Run on PiServ:

```sh
sudo systemctl is-active glances.service
curl -fsS http://127.0.0.1:61208/api/4/status
sudo ss -ltn | grep 0.0.0.0:61208
sudo ufw status numbered | grep -F 'PiServ LAN Glances API'
```

Run from a LAN or permitted tailnet client:

```sh
curl -fsS -o /dev/null -w '%{http_code}\n' http://PiServ.local:61208/api/4/status
```

The expected HTTP status is `200`. In Home Assistant, confirm that the Glances
device exposes CPU, memory, disk, network, uptime, and available temperature
entities.

## Recovery

Inspect startup failures with:

```sh
ssh admin@PiServ.local 'sudo systemctl status glances.service --no-pager'
ssh admin@PiServ.local 'sudo journalctl -u glances.service -n 100 --no-pager'
```

Reapply the base and firewall playbooks to restore the managed API listener and
IPv4 LAN policy. Do not expose the API to IPv6 or other networks without an
authentication and firewall review.
