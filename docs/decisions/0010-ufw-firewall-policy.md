# 0010: UFW Firewall Policy

## Status

Accepted and applied on 2026-07-13, including the PiServ subnet-router
forwarding rule.

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
| LAN IPv4 mDNS | Allow UDP `5353` to `224.0.0.251` from the current IPv4 LAN CIDR |
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
management policy is designed and validated.

The fork integration of `oefenweb.ufw` owns generic UFW package, policy, rule,
and logging behavior. PiServ-specific ranges, ports, interfaces, and comments
remain in `ansible/playbooks/firewall.yml`. Project task files own the
preflight assertion, explicit UFW service state, and post-apply validation.

The dependency is pinned to the reviewed fork commit while its mutation support
is under upstream review. The external role remains the source of truth for its
managed UFW configuration. When those files change, the role retains its
standard behavior of resetting UFW before rebuilding the declared policies and
rules in the same run.

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

- SSH and VNC remain available from the IPv4 LAN and tailnet.
- IPv4 mDNS remains available on the current LAN.
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

Automation validation remains pending. The controller now has verified LAN and
Tailscale SSH paths, so the firewall playbook can be applied and this validation
set rerun.

## References

- [Tailscale: Use UFW to lock down a server](https://tailscale.com/docs/how-to/secure-ubuntu-server-with-ufw)
- [Tailscale netfilter modes](https://tailscale.com/docs/reference/netfilter-modes)
- [Tailscale firewall ports](https://tailscale.com/docs/reference/faq/firewall-ports)
- [Ansible `community.general.ufw`](https://docs.ansible.com/projects/ansible/latest/collections/community/general/ufw_module.html)
- [Upstream `ansible-ufw` PR #54](https://github.com/Oefenweb/ansible-ufw/pull/54)
