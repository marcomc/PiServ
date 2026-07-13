# 0011: High-Availability Tailscale Subnet Router

## Status

Accepted. PiServ automation is implemented; tailnet route approval and
cross-router failover validation remain pending.

## Context

Remote tailnet clients need access to non-Tailscale devices on the home IPv4
LAN. A single subnet router is a host-level availability risk. PiServ is an
additional router on the same LAN and must fail over with the existing router.

PiServ previously accepted an overlapping advertised LAN route. Linux then
routed replies to directly connected LAN clients through `tailscale0`, breaking
LAN ICMP and SSH.

## Decision

PiServ participates in a high-availability subnet-router group. Every member
advertises the exact same local IPv4 prefix. Tailscale selects one router and
fails over to another available member when necessary.

PiServ automation enforces the following policy:

| Area | Policy |
| --- | --- |
| Advertised routes | Current IPv4 prefix of the default route only |
| IPv4 forwarding | Enabled persistently |
| Source NAT | Tailscale default SNAT enabled |
| Imported routes | Rejected with `--accept-routes=false` |
| UFW forwarding | Allow from `tailscale0` to the local IPv4 LAN only |
| Default routed policy | Deny |
| IPv6 subnet routing | Not configured |

Route approval and tailnet access grants remain administrative controls outside
this repository. This project configures PiServ only; peer routers are managed
by their respective projects.

## Consequences

- PiServ can serve as a backup when another router advertising the same prefix
  is unavailable.
- Direct PiServ LAN access remains local because it rejects imported routes.
- Non-Tailscale LAN devices see routed traffic as sourced from PiServ because
  Tailscale SNAT remains enabled.
- The route must be approved in the Tailscale admin console before clients can
  use PiServ as a router.
- A client on an overlapping local IPv4 network may prefer its local route and
  cannot reliably reach the home network through that prefix.

## Validation

Run the Tailscale and firewall playbooks, approve the advertised route, then
use a remote tailnet client to reach a non-Tailscale LAN device by IPv4 address.
Perform the controlled failover test in the HA subnet-routing runbook.

Observed before implementation on 2026-07-13:

```text
PiServ IPv4 forwarding: disabled
PiServ route acceptance: false
PiServ advertised local route: configured but inactive
```

## References

- [Tailscale subnet routers](https://tailscale.com/docs/features/subnet-routers)
- [Tailscale high availability](https://tailscale.com/docs/how-to/set-up-high-availability)
