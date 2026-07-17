# UFW Firewall Policy

## Table of Contents

- [Purpose](#purpose)
- [Policy](#policy)
- [Preconditions](#preconditions)
- [Apply](#apply)
- [Verify](#verify)
- [Change Rules](#change-rules)
- [Recovery](#recovery)
- [Observed PiServ State](#observed-piserv-state)

## Purpose

Apply, verify, change, and recover the PiServ UFW policy without losing LAN or
Tailscale administration access.

## Policy

| Traffic | Result |
| --- | --- |
| Established connections | Allowed by UFW state tracking |
| Outgoing host traffic | Allowed |
| Routed traffic | Denied except Tailscale to the local IPv4 LAN |
| IPv4 LAN TCP `22` | Allowed for SSH |
| IPv4 LAN TCP `5900` | Allowed for VNC |
| IPv4 LAN TCP `9090` | Allowed for Cockpit HTTPS |
| IPv4 LAN TCP `61208` | Allowed for Glances API |
| IPv4 LAN UDP `5353` to `224.0.0.251` | Allowed for mDNS |
| IPv6 LAN ingress | Denied by default |
| Ingress on `tailscale0` | Allowed |
| Routed from `tailscale0` | Allowed only to the local IPv4 LAN |
| UDP `41641` | Allowed for direct Tailscale connections |
| Other unsolicited ingress | Denied |

Tailscale stays in netfilter mode `on`; tailnet grants and ACLs remain the
identity-level access control for traffic arriving through `tailscale0`.

## Preconditions

Verify both administration paths before applying changes:

```sh
ssh admin@PiServ.local 'sudo -n true'
ssh admin@PISERV_TAILSCALE_IP 'sudo -n true'
```

Confirm the current LAN and Tailscale interfaces:

```sh
ip -4 -brief address
ip -4 route
tailscale status
tailscale ip -4
sudo sysctl -n net.ipv4.ip_forward
```

## Apply

Install role and collection dependencies, then run the playbook:

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-galaxy collection install -r ansible/requirements.yml --force
ansible-playbook ansible/playbooks/firewall.yml
```

The role dependency is pinned to the reviewed PiServ fork commit of
`oefenweb.ufw`. The role remains the source of truth for its managed UFW files.
When those files change, its standard behavior resets UFW and then rebuilds the
declared policies and rules in the same run. Verify both administration paths
before applying configuration changes.

The `--force` flags make a changed pin or collection version take effect on a
controller that already has the dependencies installed.

`piserv_firewall_lan_ipv4_cidr` is derived from the default IPv4 route rather
than a fixed physical interface. A Wi-Fi-to-Ethernet change on the same LAN
therefore needs no policy change. Override the IPv4 CIDR when the permitted
management LAN is different:

```sh
ansible-playbook ansible/playbooks/firewall.yml \
  -e piserv_firewall_lan_ipv4_cidr=192.0.2.0/24
```

IPv6 support remains enabled in UFW, but this policy intentionally permits no
IPv6 LAN ingress. Add IPv6 management rules only through a separately reviewed
and live-validated dual-stack policy.

The first live application used the equivalent UFW commands before the state
was codified:

```sh
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed
sudo ufw allow from LAN_IPV4_CIDR to any port 22 proto tcp
sudo ufw allow from LAN_IPV4_CIDR to any port 5900 proto tcp
sudo ufw allow from LAN_IPV4_CIDR to any port 9090 proto tcp
sudo ufw allow from LAN_IPV4_CIDR to any port 61208 proto tcp
sudo ufw allow from LAN_IPV4_CIDR to 224.0.0.251 port 5353 proto udp
sudo ufw allow in on tailscale0
sudo ufw route allow in on tailscale0 from 100.64.0.0/10 to LAN_IPV4_CIDR
sudo ufw allow 41641/udp
sudo ufw logging low
sudo ufw --force enable
sudo systemctl enable --now ufw.service
```

## Verify

Run on PiServ:

```sh
sudo ufw status verbose
systemctl is-enabled ufw.service
systemctl is-active ufw.service
sudo nft list ruleset
tailscale status
mountpoint /mnt/pcloud
```

Run from a LAN client:

```sh
nc -vz PiServ.local 22
nc -vz PiServ.local 5900
curl -kfsS -o /dev/null -w '%{http_code}\n' https://PiServ.local:9090/
curl -sS -o /dev/null -w '%{http_code}\n' http://PiServ.local:61208/api/4/status
```

Run from a Tailscale client:

```sh
tailscale ping piserv
nc -vz PISERV_TAILSCALE_IP 22
nc -vz PISERV_TAILSCALE_IP 5900
curl -kfsS -o /dev/null -w '%{http_code}\n' https://PISERV_TAILSCALE_IP:9090/
curl -sS -o /dev/null -w '%{http_code}\n' http://PISERV_TAILSCALE_IP:61208/api/4/status
ssh admin@PISERV_TAILSCALE_IP true
```

Run from a remote Tailscale client against a non-Tailscale LAN device:

```sh
ping LAN_DEVICE_IPV4
nc -vz LAN_DEVICE_IPV4 PORT
```

Re-run the playbook. The steady-state result must be `changed=0`.

## Change Rules

Add host-specific desired rules to `piserv_firewall_rules` in
`ansible/playbooks/firewall.yml`.

Rule-only UFW runs are additive. Removing a rule from the list does not remove
it from the host. To withdraw a rule:

1. Keep the matching rule in the playbook and add `delete: true`.
2. Run the playbook and verify the rule is absent.
3. Remove the bounded deletion entry from the steady-state playbook.

When Ethernet is added, verify whether it uses the same IPv4 LAN CIDR. Add an
explicit additional rule set if it introduces a different trusted network.
IPv6 management access requires a separately reviewed dual-stack policy.

## Recovery

If a rule change blocks ordinary LAN access, connect through the already
verified Tailscale path or use the physical touchscreen and keyboard.

Inspect and disable UFW temporarily:

```sh
sudo ufw status numbered
sudo ufw disable
```

Restore the managed policy:

```sh
ansible-playbook ansible/playbooks/firewall.yml
```

Do not run `ufw reset` manually during ordinary recovery. The role may reset UFW
after a managed configuration change and then rebuild the declared allowlist in
the same playbook run.

## Observed PiServ State

Validated on 2026-07-13:

| Check | Result |
| --- | --- |
| UFW package | `0.36.2-9` |
| UFW runtime | Active |
| UFW service | Enabled, active |
| Default policies | Incoming deny, outgoing allow, routed deny |
| LAN allowlist | IPv4 SSH, VNC, Cockpit HTTPS, mDNS |
| LAN Glances API | TCP `61208` from the IPv4 LAN |
| IPv6 LAN ingress | Denied by default |
| Tailscale allowlist | `tailscale0`, UDP `41641` |
| Tailscale routed allowlist | `tailscale0` to local IPv4 LAN |
| Tailscale after enable | Connected, direct peer path |
| New Tailscale SSH connection | Passed |
| New Tailscale VNC TCP connection | Passed |
| Cockpit LAN HTTPS connection | Passed on 2026-07-16 |
| pCloud mount | Remained mounted |

The same validation found that PiServ accepted an overlapping Tailscale LAN
route. That sent replies to local clients through `tailscale0`, so direct LAN
connections could not complete. Disabling accepted routes restored LAN access.
The default routed policy remains deny. The explicit Tailscale-to-LAN route rule
is required for PiServ's HA subnet-router participation.

The firewall automation was applied on 2026-07-13. A second playbook run
returned `changed=0`; LAN and Tailscale SSH remained available. The routed rule
is ready for PiServ's advertised subnet route after Tailscale admin-console
approval.
