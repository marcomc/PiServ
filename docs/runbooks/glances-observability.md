# Glances Observability

## Table of Contents

- [Purpose](#purpose)
- [Apply](#apply)
- [Access](#access)
- [Validation](#validation)
- [Recovery](#recovery)

## Purpose

Operate PiServ's low-overhead Glances JSON API. The service is loopback-only
and does not add a UFW rule or an unauthenticated LAN listener.

## Apply

```sh
ansible-playbook ansible/playbooks/piserv-base.yml
```

The base role installs `glances` and `lm-sensors` without optional integrations,
then overrides the Debian `glances.service` to use API-only mode on
`127.0.0.1:61208`.

## Access

Forward the loopback port from a separate local terminal:

```sh
ssh -N -L 61208:127.0.0.1:61208 admin@PiServ.local
```

Query the API from another terminal:

```sh
curl -fsS http://127.0.0.1:61208/api/4/status
curl -fsS http://127.0.0.1:61208/api/4/cpu
```

The API has no HTTP credentials because the service listens only on PiServ's
loopback interface. SSH public-key authentication is the access boundary.

For an interactive terminal view, connect to PiServ with SSH and run:

```sh
glances
```

The Debian 13 package's web UI is disabled. Its static asset directory is
missing, so `glances --webserver` without `--disable-webui` fails at startup.

## Validation

The 2026-07-16 live deployment confirmed Glances `4.3.1+dfsg-1` as active,
the API status and CPU endpoints as responsive, and the listener as
`127.0.0.1:61208`. A connection to PiServ's LAN address on port `61208` was
refused.

Repeat the checks with:

```sh
ssh admin@PiServ.local 'sudo systemctl is-active glances.service'
ssh admin@PiServ.local 'curl -fsS http://127.0.0.1:61208/api/4/status'
ssh admin@PiServ.local 'sudo ss -ltn | grep 127.0.0.1:61208'
```

The base playbook also validates the JSON status response and rejects wildcard
listeners on port `61208`.

## Recovery

Inspect startup failures with:

```sh
ssh admin@PiServ.local 'sudo systemctl status glances.service --no-pager'
ssh admin@PiServ.local 'sudo journalctl -u glances.service -n 100 --no-pager'
```

Reapply the base playbook to restore the managed package and systemd drop-in.
Do not bind the API to the LAN or Tailscale interfaces without adding an
explicit authentication and firewall decision first.
