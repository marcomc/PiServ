# 0010: UFW Firewall Policy

## Status

Accepted and applied on 2026-07-13, including the PiServ subnet-router
forwarding rule. Reaffirmed on 2026-07-28: unsolicited IPv6 LAN management
access remains denied.

## Context

PiServ must remain reachable through the local LAN and Tailscale while denying
unnecessary access to other listening services. Tailscale was connected before
the firewall was enabled, providing a second verified administration path.

The live host had no conventional firewall. Tailscale's default netfilter mode
already accepted `tailscale0` traffic, rejected spoofed CGNAT source addresses,
and accepted Tailscale protocol traffic.

## Decision

PiServ uses UFW for the conventional host firewall and leaves Tailscale in its
default netfilter mode.

| Area | Policy |
| --- | --- |
| Incoming default | Deny |
| Outgoing default | Allow |
| Routed default | Deny |
| Logging | Low |
| LAN IPv4 SSH | Allow TCP `22` from the current IPv4 LAN CIDR |
| LAN IPv4 VNC | Allow TCP `5900` from the current IPv4 LAN CIDR |
| LAN IPv4 Cockpit | Allow TCP `9090` from the current IPv4 LAN CIDR |
| LAN IPv4 Glances | Allow TCP `61208` from the current IPv4 LAN CIDR |
| Jackett Docker ingress | Allow TCP `9117` from the current IPv4 LAN and `tailscale0` only |
| LAN IPv4 mDNS | Allow UDP `5353` from the current IPv4 LAN CIDR, including multicast and unicast mDNS queries |
| LAN IPv6 ingress | Deny by default |
| Tailnet ingress | Allow traffic arriving on `tailscale0` |
| Tailscale subnet routing | Allow forwarded tailnet IPv4 traffic only to the local IPv4 LAN |
| Tailscale direct path | Allow UDP `41641` |
| Other LAN ingress | Deny by default |

The PiServ playbook derives the current IPv4 LAN CIDR from the default IPv4
route, not a fixed physical interface. Moving the default route from Wi-Fi to
Ethernet on the same LAN therefore needs no policy change. Additional IPv4 LAN
ranges must be configured explicitly when the network topology changes.

UFW IPv6 support remains enabled, but PiServ has no IPv6 LAN allow rules. This
keeps unsolicited IPv6 LAN traffic denied until an explicitly scoped dual-stack
management policy is designed and validated. The project has decided not to
add that dual-stack management policy unless the operational requirement
changes.

The fork integration of `oefenweb.ufw` owns generic UFW package, policy, rule,
and logging behavior. PiServ-specific ranges, ports, interfaces, and comments
remain in `ansible/playbooks/firewall.yml`. Project task files own the
preflight assertion, explicit UFW service state, and post-apply validation.
PiServ also removes UFW's package-default mDNS pre-rules from `before.rules`
and `before6.rules`; otherwise multicast UDP `5353` bypasses the declared LAN
source restriction.

The dependency is pinned to the reviewed fork commit while its mutation support
is under upstream review. The external role remains the source of truth for its
managed UFW configuration. When those files change, the role retains its
standard behavior of resetting UFW before rebuilding the declared policies and
rules in the same run.

Docker publishes bridge-network ports through NAT before UFW's normal input
chain. The Jackett playbook therefore owns an explicit `DOCKER-USER` policy:
it allows TCP `9117` from the current IPv4 LAN and traffic arriving on
`tailscale0`, then drops other sources before Docker's bridge accept rule. This
is separate from the UFW allowlist and must be validated with `iptables -S
DOCKER-USER` after every Docker restart.

## Tailscale Boundary

Tailscale remains in netfilter mode `on`. In this mode, Tailscale evaluates its
own rules early and accepts tailnet traffic arriving through `tailscale0`.
Tailnet grants and ACLs therefore control which tailnet identities may connect;
the explicit UFW interface rule records that PiServ accepts authenticated
tailnet ingress.

The default routed policy remains deny. One explicit routed rule permits only
Tailscale CGNAT source traffic arriving on `tailscale0` to reach PiServ's local
IPv4 LAN. Kernel forwarding and Tailscale SNAT are configured by the Tailscale
playbook. See decision 0011 for the high-availability router policy.

## Consequences

- SSH, VNC, and Cockpit remain available from the IPv4 LAN and tailnet.
- Jackett remains available from the IPv4 LAN and Tailnet through its Tailscale
  hostname/domain, but not from other Docker-published ingress sources.
- The HTTP Basic-authenticated Glances API is available to the current IPv4 LAN
  and to tailnet identities allowed by Tailnet ACLs; IPv6 LAN ingress remains
  denied.
- IPv4 mDNS remains available on the current LAN. The rule intentionally does
  not restrict the destination to `224.0.0.251`: Apple mDNS clients may send
  cache-refresh or question-response queries directly to the host's UDP `5353`
  address.
- IPv6 LAN ingress remains denied by default.
- pCloud and other incidental listeners are blocked from unsolicited LAN
  access but remain reachable to permitted tailnet identities.
- Tailscale can continue using direct UDP peer connections.
- Adding a network service now requires an explicit IPv4 or IPv6 LAN rule, or a
  deliberate decision to expose it only through Tailscale.
- Rule-only UFW runs are additive. Removing a desired rule requires a bounded
  `delete: true` step before the rule definition is removed.
- The fork role supports bounded rule deletion and explicit insertion order;
  PiServ does not use those controls in its steady-state policy today.

## Validation

Live validation on PiServ:

```sh
sudo ufw status verbose
systemctl is-enabled ufw.service
systemctl is-active ufw.service
tailscale status
mountpoint /mnt/pcloud
```

Observed result:

```text
UFW active
incoming deny, outgoing allow, routed deny
ufw.service enabled and active
new SSH and VNC connections over Tailscale succeeded
Tailscale remained on a direct peer path
pCloud remained mounted
```

Automation validation on 2026-07-13 applied
`ansible/playbooks/firewall.yml`; a repeat run completed with `changed=0` while
new LAN and Tailscale SSH connections remained available. Cockpit port `9090`
and Glances API port `61208` were added and LAN-validated on 2026-07-16.

On 2026-07-28, live `sudo ufw status verbose` validation showed no IPv6 LAN
allow rules. IPv6 listeners that bind wildcard addresses remain protected by
the default-deny incoming policy; IPv6 ingress through `tailscale0` remains
the separate authenticated Tailnet boundary.

## References

- [Tailscale: Use UFW to lock down a server](https://tailscale.com/docs/how-to/secure-ubuntu-server-with-ufw)
- [Tailscale netfilter modes](https://tailscale.com/docs/reference/netfilter-modes)
- [Tailscale firewall ports](https://tailscale.com/docs/reference/faq/firewall-ports)
- [Ansible `community.general.ufw`](https://docs.ansible.com/projects/ansible/latest/collections/community/general/ufw_module.html)
- [Docker packet filtering and UFW](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
- [Upstream `ansible-ufw` PR #54](https://github.com/Oefenweb/ansible-ufw/pull/54)
