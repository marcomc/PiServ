# 0007: Base Security Posture

## Status

Partially implemented on 2026-07-08.

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
| SSH user access | Keep key-based SSH for the sudo-enabled `operator` user |
| Firewall reachability | Allow selected LAN services and Tailscale interface ingress |
| Tailscale | Install before enabling the restrictive firewall |
| VNC | Keep VNC active |
| VNC display model | Investigate mirroring the touchscreen display instead of a separate VNC screen |
| `rpcbind` and NFS | Disable unless a concrete NFS requirement appears |
| CUPS | Disable |
| Bluetooth | Keep available for future Home Assistant Bluetooth beacon triangulation |
| Updates | Enable unattended security updates and automatic reboots |
| Cloud-init | Disable because PiServ will be configured by Ansible after SSH is reachable |

## Open Decisions

| Area | Recommendation |
| --- | --- |
| Users | Keep `operator` as the only human sudo operator for now; add service-specific users only when a daemon needs file ownership or privilege isolation |

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
- VNC remains available, but its display behavior needs a separate validation
  pass.
- Disabling `rpcbind`, NFS helpers, and CUPS reduces exposed surface area.
- Keeping Bluetooth trades some local attack surface for future Home Assistant
  integration value.
- Automatic reboots improve patch completion but can interrupt local display or
  long-running jobs; timers should avoid podcast sync windows.

## Validation

Live validation on PiServ on 2026-07-08:

| Check | Result |
| --- | --- |
| SSH root-login hardening | `permitrootlogin no` |
| SSH operator access | `operator@piserv.example.com` remained reachable |
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
| Firewall automation | Pending live validation |

Still pending:

- Apply and validate the firewall automation.
- Validate VNC behavior against the physical touchscreen session.
- Decide the final human and service user-account policy.
- Keep `ansible/playbooks/piserv-base.yml` as the reproduction path for the
  implemented baseline hardening.
