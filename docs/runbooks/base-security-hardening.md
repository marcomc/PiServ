# Base Security Hardening

## Table of Contents

- [Purpose](#purpose)
- [Applied State](#applied-state)
- [Live Commands](#live-commands)
- [Validation](#validation)
- [Follow-Up](#follow-up)

## Purpose

Track the first live hardening pass applied to PiServ after the baseline
inventory.

## Applied State

Applied on 2026-07-08.

| Area | State |
| --- | --- |
| SSH root login | Disabled with `PermitRootLogin no` |
| SSH password auth | Disabled |
| SSH keyboard-interactive auth | Disabled |
| SSH pubkey auth | Enabled |
| CUPS | Disabled and inactive |
| `rpcbind` | Disabled and inactive |
| NFS block mapper | Disabled and inactive |
| Unattended upgrades | Installed, enabled, and active |
| Automatic reboot | Enabled at `06:30` |
| Firewall | Not enabled yet; pending Tailscale access model |
| VNC | Left enabled |
| Bluetooth | Left enabled |
| Cloud-init | Disabled by marker file; package left installed |

Unattended upgrades currently allow Debian `trixie`, Debian `trixie-updates`,
Debian security, and Raspberry Pi Foundation package origins.

## Live Commands

SSH hardening was applied with:

```sh
ssh operator@piserv.example.com 'sudo install -o root -g root -m 0644 /tmp/99-piserv-hardening.conf /etc/ssh/sshd_config.d/99-piserv-hardening.conf'
ssh operator@piserv.example.com 'sudo sshd -t && sudo systemctl reload ssh.service'
```

The installed SSH drop-in is:

```text
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

Service exposure was reduced with:

```sh
ssh operator@piserv.example.com 'sudo systemctl disable --now cups.service cups.socket'
ssh operator@piserv.example.com 'sudo systemctl disable --now rpcbind.service rpcbind.socket nfs-blkmap.service'
```

Unattended upgrades were installed and configured with:

```sh
ssh operator@piserv.example.com 'sudo apt-get update'
ssh operator@piserv.example.com 'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades'
```

The active PiServ unattended-upgrades override is:

```text
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=${distro_codename},label=Debian";
        "origin=Debian,codename=${distro_codename}-updates,label=Debian";
        "origin=Debian,codename=${distro_codename},label=Debian-Security";
        "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
        "origin=Raspberry Pi Foundation,label=Raspberry Pi Foundation";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "06:30";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
```

Cloud-init was disabled without uninstalling the package:

```sh
ssh operator@piserv.example.com 'sudo install -o root -g root -m 0644 /tmp/cloud-init.disabled /etc/cloud/cloud-init.disabled'
ssh operator@piserv.example.com 'sudo systemctl disable --now cloud-init-local.service cloud-init-network.service cloud-init-main.service cloud-config.service cloud-final.service'
```

## Validation

| Check | Observed result |
| --- | --- |
| SSH config test | `sshd -t` passed |
| Effective SSH root login | `permitrootlogin no` |
| Effective SSH password auth | `passwordauthentication no` |
| Effective SSH pubkey auth | `pubkeyauthentication yes` |
| Admin SSH path | `operator@piserv.example.com` remained reachable |
| Admin sudo | `sudo -n true` passed |
| CUPS units | `disabled`, `inactive` |
| `rpcbind` units | `disabled`, `inactive` |
| NFS block mapper | `disabled`, `inactive` |
| Port `111` | No longer listening |
| Unattended upgrades package | `2.12` |
| Unattended upgrades service | `enabled`, `active` |
| Dry run | Completed with no pending unattended upgrades |
| Cloud-init status | `disabled`, `disabled-by-marker-file` |
| Cloud-init units | `disabled`, `inactive` |
| Ansible reproduction | `piserv-base.yml` completed with `changed=0` |

Current remaining listening sockets after this pass:

| Bind | Process | Reason |
| --- | --- | --- |
| `0.0.0.0:22`, `[::]:22` | `sshd` | Administration |
| `*:5900` | `wayvnc` | VNC retained |
| `0.0.0.0:41609` | `pcloudcc` | pCloud client |
| `0.0.0.0:42420/udp` | `pcloudcc` | pCloud client |
| `*:5353/udp` plus dynamic UDP ports | `avahi-daemon` | mDNS |

An attempted `operator@localhost` SSH test failed because localhost is not in the
known-hosts file; it was not a service failure.

## Follow-Up

- Install Tailscale before enabling a restrictive firewall.
- Define the firewall allowlist for LAN and Tailscale clients.
- Investigate VNC mirroring of the physical touchscreen display.
- Reapply this baseline with
  `ansible-playbook ansible/playbooks/piserv-base.yml`.
