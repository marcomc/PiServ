# 0010: UFW Firewall Policy

## Status

Accepted and implemented on 2026-07-13.

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
| LAN SSH | Allow TCP `22` from the current LAN CIDR |
| LAN VNC | Allow TCP `5900` from the current LAN CIDR |
| LAN mDNS | Allow UDP `5353` to `224.0.0.251` from the current LAN CIDR |
| Tailnet ingress | Allow traffic arriving on `tailscale0` |
| Tailscale direct path | Allow UDP `41641` |
| Other LAN ingress | Deny by default |

The PiServ playbook derives the current LAN CIDR from the default IPv4 Ansible
fact. Additional or replacement LAN ranges must be added explicitly when the
network topology changes.

The generic `firewall` role owns UFW package, policy, serial rule application,
logging, service, and validation behavior. PiServ-specific ranges, ports,
interfaces, and comments remain in `ansible/playbooks/firewall.yml`.

## Tailscale Boundary

Tailscale remains in netfilter mode `on`. In this mode, Tailscale evaluates its
own rules early and accepts tailnet traffic arriving through `tailscale0`.
Tailnet grants and ACLs therefore control which tailnet identities may connect;
the explicit UFW interface rule records that PiServ accepts authenticated
tailnet ingress.

The firewall does not enable subnet routing. Routed traffic is denied and
kernel forwarding remains disabled. PiServ currently advertises a LAN route,
so completing or removing that route is tracked separately.

## Consequences

- SSH and VNC remain available from the LAN and tailnet.
- mDNS remains available on the current LAN.
- pCloud and other incidental listeners are blocked from unsolicited LAN
  access but remain reachable to permitted tailnet identities.
- Tailscale can continue using direct UDP peer connections.
- Adding a network service now requires an explicit LAN rule or a deliberate
  decision to expose it only through Tailscale.
- UFW rule management is additive. Removing a desired rule requires a bounded
  `delete: true` migration before the rule definition is removed.

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
firewall playbook: changed=0, failed=0
```

## References

- [Tailscale: Use UFW to lock down a server](https://tailscale.com/docs/how-to/secure-ubuntu-server-with-ufw)
- [Tailscale netfilter modes](https://tailscale.com/docs/reference/netfilter-modes)
- [Tailscale firewall ports](https://tailscale.com/docs/reference/faq/firewall-ports)
- [Ansible `community.general.ufw`](https://docs.ansible.com/projects/ansible/latest/collections/community/general/ufw_module.html)
