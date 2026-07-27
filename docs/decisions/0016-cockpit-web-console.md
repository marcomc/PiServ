# 0016: Cockpit Web Console and Extensions

## Status

Accepted and implemented on 2026-07-27.

## Context

PiServ needs a browser-accessible view of host resources and a constrained
administration interface. Glances provides metrics through its JSON API, but
its Debian 13 web UI is unavailable because the package omits required static
assets.

## Decision

Install Debian's Cockpit packages through the project-local `base` role and
enable `cockpit.socket`.

| Area | Decision |
| --- | --- |
| Endpoint | HTTPS on TCP `9090`, socket activated by `cockpit.socket` |
| LAN firewall | Allow TCP `9090` only from the current IPv4 LAN CIDR |
| Tailnet | Existing `tailscale0` ingress policy; Tailnet ACLs control access |
| Authentication | Host PAM policy; use local `admin`, while root remains disallowed |
| Certificate | Debian-generated self-signed certificate until a managed certificate is required |
| Package scope | `cockpit`, `cockpit-storaged`, `cockpit-sosreport`, and `cockpit-packagekit` |

The base role asserts that Cockpit's local HTTPS login page responds with HTTP
`200`. It does not create users, manage passwords, or automate browser login.

## Consequences

- Operators can inspect resources at `https://PiServ.local:9090`.
- The first browser connection requires validating and accepting the self-signed
  certificate.
- Cockpit uses PAM independently of SSH's password-authentication setting.
- The console has an intentional network exposure, limited by UFW to the LAN
  and by existing Tailnet ACLs for Tailnet access.
- Storage changes remain Ansible-controlled even though Cockpit Storage can
  perform interactive disk operations.
- PackageKit provides an emergency/operator package view; Ansible and
  unattended-upgrades remain the normal package-management authority.

## Validation

On 2026-07-27, Debian Cockpit `337-1+deb13u1` and the three selected extension
packages installed successfully. `cockpit.socket` remained enabled and active;
`cockpit-bridge --packages` reported `storage`, `sosreport`, and `updates`, and
a local HTTPS request returned the Cockpit login page.

The installed package attempted to use `sscg` for a self-signed certificate,
then successfully used its OpenSSL fallback because `sscg` was not installed.
