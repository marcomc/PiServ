# 0007: Base Security Posture

## Status

Accepted and implemented on 2026-07-14.

## Context

The live baseline captured on 2026-07-08 showed PiServ reachable on the LAN via
Wi-Fi, with SSH, VNC, `rpcbind`, mDNS, and a `pcloudcc` listener exposed. No
local firewall was configured.

PiServ must remain reachable from the LAN and from future Tailscale-connected
devices. It also has an attached touchscreen and should keep local interactive
capability.

## Decisions

| Area | Decision |
| --- | --- |
| SSH root login | Disable root login as long as a sudo-enabled user can still SSH |
| SSH user access | Keep key-based SSH for the sudo-enabled `admin` user |
| Firewall reachability | Allow selected LAN services and Tailscale interface ingress |
| Tailscale | Install before enabling the restrictive firewall |
| VNC | Keep VNC active |
| VNC display model | Capture the physical touchscreen output `DSI-1` |
| `rpcbind` and NFS | Disable unless a concrete NFS requirement appears |
| CUPS | Disable |
| Bluetooth | Keep available for future Home Assistant Bluetooth beacon triangulation |
| Updates | Enable unattended security updates and automatic reboots |
| Cloud-init | Disable because PiServ will be configured by Ansible after SSH is reachable |

## Related Decisions

- [PiServ user-account policy](0012-user-account-policy.md) records the accepted
  account model.
- [VNC touchscreen output](0013-vnc-touchscreen-output.md) records the
  display-selection implementation.
- [Freenove hardware cleanup state](0014-freenove-hardware-cleanup.md) records
  the accepted physical fan-LED limitation.

## Cloud-Init Assessment

Cloud-init is useful in a home network when the host is reimaged often and the
first boot must be driven by a seed or image customisation. Examples include:

| Use | Fit for PiServ |
| --- | --- |
| First-boot hostname, SSH keys, packages, and users | Useful only if PiServ images are rebuilt from scratch often |
| Network bootstrap | Less useful because Wi-Fi and Ethernet should be managed by Ansible/netplan after install |
| One-shot provisioning | Overlaps with the planned Ansible bootstrap role |
| Reproducible disaster recovery | Better handled here by Ansible after SSH is reachable |

For PiServ, cloud-init is not the preferred long-term configuration layer. It
has been disabled because the recovery model is SSH followed by Ansible.

## Consequences

- SSH remains the primary administration path.
- LAN and Tailscale ingress is now managed by the separate UFW firewall
  playbook.
- VNC remains available and is managed to capture the physical touchscreen.
- Disabling `rpcbind`, NFS helpers, and CUPS reduces exposed surface area.
- Keeping Bluetooth trades some local attack surface for future Home Assistant
  integration value.
- Automatic reboots improve patch completion but can interrupt local display or
  long-running jobs; timers should avoid podcast sync windows.

## Validation

Live validation on PiServ:

| Check | Result |
| --- | --- |
| SSH root-login hardening | `permitrootlogin no` |
| SSH admin access | `admin@PiServ.local` remained reachable |
| Admin sudo | `sudo -n true` passed |
| CUPS | Disabled and inactive |
| `rpcbind` and NFS helper | Disabled and inactive |
| Port `111` | No longer listening |
| Unattended upgrades | Installed, enabled, active |
| Unattended-upgrades dry run | Completed successfully |
| Cloud-init | Disabled by `/etc/cloud/cloud-init.disabled`; units disabled and inactive |
| Ansible reproduction | `ansible/playbooks/piserv-base.yml` completed with `changed=0` |
| Tailscale access | Connected; new OpenSSH connection passed |
| UFW firewall | Active with incoming and routed traffic denied by default |
| Firewall automation | Applied on 2026-07-13; repeat run completed with `changed=0` |
| VNC output | Control socket reports `DSI-1` as the active captured output |
| User policy | `admin` exists in `sudo`; no `operator` account exists |

Keep `ansible/playbooks/piserv-base.yml` as the reproduction path for the
implemented baseline hardening. The remaining physical Freenove fan-LED
limitation is documented in decision 0014; it is not software-controllable
through the FNK0100 expansion API.
