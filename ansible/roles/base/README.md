# Ansible Role: base

Configure PiServ's base host policy.

## Table of Contents

- [Purpose](#purpose)
- [Role Variables](#role-variables)
- [Example Playbook](#example-playbook)
- [Behavior](#behavior)
- [Validation](#validation)

## Purpose

This project-local role codifies live PiServ baseline hardening:

- SSH root-login and password-auth policy
- VNC capture selection for the physical touchscreen output
- disabled system services that are not part of the production baseline
- unattended upgrades and reboot window
- boot notification service
- cloud-init disabled state

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `base_manage_ssh` | `true` | Manage SSH daemon hardening |
| `base_ssh_dropin_path` | `/etc/ssh/sshd_config.d/99-piserv-hardening.conf` | SSH drop-in path |
| `base_ssh_permit_root_login` | `no` | Effective `PermitRootLogin` value |
| `base_ssh_password_authentication` | `no` | Effective `PasswordAuthentication` value |
| `base_ssh_kbd_interactive_authentication` | `no` | Effective keyboard-interactive auth value |
| `base_ssh_pubkey_authentication` | `yes` | Effective public-key auth value |
| `base_manage_vnc` | `true` | Manage the VNC service output selection |
| `base_vnc_output` | `DSI-1` | Wayland output captured by VNC |
| `base_vnc_run_wrapper_path` | `/usr/local/libexec/piserv-wayvnc-run` | Project-owned VNC startup wrapper |
| `base_manage_disabled_services` | `true` | Disable selected systemd units |
| `base_disabled_systemd_units` | CUPS, `rpcbind`, NFS block mapper | Units disabled when present |
| `base_manage_unattended_upgrades` | `true` | Manage unattended upgrades |
| `base_unattended_automatic_reboot_time` | `06:30` | Reboot window used only when upgrades require reboot |
| `base_unattended_origins_patterns` | Debian and Raspberry Pi origins | Allowed unattended-upgrades origins |
| `base_unattended_mail_to` | `root` | Local recipient for unattended-upgrades reports |
| `base_unattended_mail_report` | `on-change` | Report when upgrades or errors occur |
| `base_manage_reboot_notification` | `true` | Install and enable boot notification service |
| `base_reboot_notification_recipient` | `root` | Local recipient for boot notification |
| `base_reboot_notification_condition_path` | `/etc/msmtprc` | Path required before boot notification runs |
| `base_manage_cloud_init` | `true` | Manage cloud-init state |
| `base_cloud_init_disable` | `true` | Disable cloud-init with marker file and units |

See `defaults/main.yml` for the full variable set.

## Example Playbook

```yaml
---
- name: Configure PiServ base host policy
  hosts: piserv
  gather_facts: true
  roles:
    - role: base
```

## Behavior

The role validates SSH configuration before reloading `ssh.service`, then reads
the effective SSH daemon policy and asserts the expected values.

Services listed in `base_disabled_systemd_units` are disabled only when their
unit files exist on the target.

Unattended upgrades are installed, enabled, and dry-run validated by default.
Automatic reboot is enabled only for upgrades that require a reboot. Reports are
sent to local recipient `root` when upgrades or errors occur.

The boot notification service is enabled by default, but systemd skips it until
`base_reboot_notification_condition_path` exists. Configure a mail transport
with a separate role before expecting delivery.

Cloud-init is disabled with `/etc/cloud/cloud-init.disabled`; the package is not
removed.

The VNC service is kept enabled and is started with the configured Wayland
output. PiServ selects `DSI-1`, the attached 4.3-inch touchscreen, instead of
the first output selected by the Raspberry Pi OS wrapper.

## Validation

```sh
ANSIBLE_ROLES_PATH=.. ansible-playbook --syntax-check tests/test.yml
ansible-lint ansible/playbooks/piserv-base.yml ansible/roles/base
```
