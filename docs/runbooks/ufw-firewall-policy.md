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
| Routed traffic | Denied |
| LAN TCP `22` | Allowed for SSH |
| LAN TCP `5900` | Allowed for VNC |
| LAN UDP `5353` to `224.0.0.251` | Allowed for mDNS |
| Ingress on `tailscale0` | Allowed |
| UDP `41641` | Allowed for direct Tailscale connections |
| Other unsolicited ingress | Denied |

Tailscale stays in netfilter mode `on`; tailnet grants and ACLs remain the
identity-level access control for traffic arriving through `tailscale0`.

## Preconditions

Verify both administration paths before applying changes:

```sh
ssh operator@piserv.example.com 'sudo -n true'
ssh operator@PISERV_TAILSCALE_IP 'sudo -n true'
```

Confirm the current LAN and Tailscale interfaces:

```sh
ip -4 -brief address
ip -4 route
tailscale status
tailscale ip -4
```

## Apply

Install role and collection dependencies, then run the playbook:

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook ansible/playbooks/firewall.yml
```

The role dependency is pinned to the reviewed PiServ fork commit of
`oefenweb.ufw`. The role remains the source of truth for its managed UFW files.
When those files change, its standard behavior resets UFW and then rebuilds the
declared policies and rules in the same run. Verify both administration paths
before applying configuration changes.

`piserv_firewall_lan_interface` defaults to `wlan0`, and
`piserv_firewall_lan_cidr` is derived from that interface. This prevents a
future default-route change from implicitly trusting a different network.
Override the CIDR when the permitted management LAN is different:

```sh
ansible-playbook ansible/playbooks/firewall.yml \
  -e piserv_firewall_lan_cidr=192.0.2.0/24
```

The first live application used the equivalent UFW commands before the state
was codified:

```sh
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed
sudo ufw allow from LAN_CIDR to any port 22 proto tcp
sudo ufw allow from LAN_CIDR to any port 5900 proto tcp
sudo ufw allow from LAN_CIDR to 224.0.0.251 port 5353 proto udp
sudo ufw allow in on tailscale0
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
nc -vz piserv.example.com 22
nc -vz piserv.example.com 5900
```

Run from a Tailscale client:

```sh
tailscale ping piserv
nc -vz PISERV_TAILSCALE_IP 22
nc -vz PISERV_TAILSCALE_IP 5900
ssh operator@PISERV_TAILSCALE_IP true
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

When Ethernet is added, verify whether it uses the same LAN CIDR. Add an
explicit additional rule set if it introduces a different trusted network.

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
| LAN allowlist | SSH, VNC, mDNS |
| Tailscale allowlist | `tailscale0`, UDP `41641` |
| Tailscale after enable | Connected, direct peer path |
| New Tailscale SSH connection | Passed |
| New Tailscale VNC TCP connection | Passed |
| pCloud mount | Remained mounted |

The same validation found a pre-existing Tailscale LAN route advertisement
while IPv4 and IPv6 forwarding were disabled. Firewall routed traffic remains
denied; completing or removing subnet routing is tracked separately.

The firewall automation has not yet been applied because the controller could
not reach PiServ on 2026-07-13. Re-establish a verified LAN or Tailscale SSH
path, run the Apply section, and update this observed-state table with the
playbook result before treating the automation as complete.
