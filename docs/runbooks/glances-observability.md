# Glances Observability

## Table of Contents

- [Purpose](#purpose)
- [Apply](#apply)
- [Authentication Bootstrap](#authentication-bootstrap)
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

The base role installs `glances`, `lm-sensors`, `python3-uvicorn`, and
`python3-jinja2`. Uvicorn and Jinja2 are required because the Debian package
lists them as recommendations while the role deliberately disables optional
package recommendations. The role then starts `glances.service` in API-only
mode on IPv4 port `61208`. UFW permits the port from PiServ's current IPv4 LAN
CIDR. The existing `tailscale0` policy also permits tailnet clients according to
tailnet ACLs. Both network paths require Glances HTTP Basic authentication.

## Authentication Bootstrap

The first base-role apply generates a random password on PiServ and writes only
its salted hash to `/etc/glances/glances.pwd` as `root:glances` with mode
`0640`. The clear bootstrap password is stored separately as
`/etc/glances/piserv-glances-bootstrap-password`, readable only by `root` with
mode `0600`; it is not stored in Ansible variables, systemd, or this repository.

Retrieve it once, configure Home Assistant, then remove the clear bootstrap
file. Removing it does not change the active Glances password.

```sh
ssh admin@PiServ.local 'sudo cat /etc/glances/piserv-glances-bootstrap-password'
ssh admin@PiServ.local 'sudo rm /etc/glances/piserv-glances-bootstrap-password'
```

## LAN and Home Assistant Access

Query the API from any IPv4 LAN client after entering the bootstrap password:

```sh
read -rs GLANCES_PASSWORD
curl --fail --silent --show-error --user "glances:${GLANCES_PASSWORD}" http://PiServ.local:61208/api/4/status
unset GLANCES_PASSWORD
```

In Home Assistant, add the **Glances** integration from **Settings > Devices &
services**. Use `PiServ.local` as the host, `61208` as the port, the username
`glances`, and the retrieved bootstrap password. If the host resolver attempts
IPv6 first, use PiServ's current IPv4 address instead because the API
intentionally has no IPv6 listener.

The current IPv4 LAN and authenticated tailnet clients allowed by tailnet ACLs
can reach TCP `61208`, so both paths use the same HTTP Basic credentials. Do
not expose TCP `61208` to other networks without TLS, authentication, and a
firewall decision.

Direct exposure is an explicitly accepted residual risk only for this trusted
LAN and ACL-controlled Tailnet boundary. Unattended upgrades install Debian
security fixes when they are available; they do not replace a network-boundary
review before expanding access.

## Local Access

Query the local API on PiServ:

```sh
curl --fail --silent --show-error --user glances http://127.0.0.1:61208/api/4/status
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
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:61208/api/4/status
sudo ss -ltn | grep 0.0.0.0:61208
sudo ufw status numbered | grep -F 'PiServ LAN Glances API'
```

Run from a LAN or permitted tailnet client:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' http://PiServ.local:61208/api/4/status
```

The expected unauthenticated HTTP status is `401`; authenticated API requests
return `200`. In Home Assistant, confirm that the Glances device exposes CPU,
memory, disk, network, uptime, and available temperature entities.

## Recovery

Inspect startup failures with:

```sh
ssh admin@PiServ.local 'sudo systemctl status glances.service --no-pager'
ssh admin@PiServ.local 'sudo journalctl -u glances.service -n 100 --no-pager'
```

Reapply the base and firewall playbooks to restore the managed API listener,
authentication, and IPv4 LAN policy. If the bootstrap password was lost before
it was configured in Home Assistant, remove both password files and reapply the
base playbook to generate a new one. Do not expose the API to IPv6 or other
networks without TLS, authentication, and firewall review.
