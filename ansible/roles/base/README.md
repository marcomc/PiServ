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
- Glances API-only system observability with loopback-safe defaults
- Cockpit HTTPS web console for system administration
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
| `base_vnc_output_selector_path` | `/usr/local/libexec/piserv-wayvnc-select-output` | Output-selection command |
| `base_vnc_output_selector_delay_seconds` | `2` | Delay before reading outputs after VNC starts |
| `base_vnc_output_selector_timeout_seconds` | `30` | Maximum selector and validation wait time |
| `base_manage_glances` | `true` | Install and manage the local Glances API service |
| `base_glances_packages` | `glances`, `lm-sensors`, `python3-uvicorn`, `python3-jinja2` | API, sensor, and webserver runtime packages |
| `base_glances_dropin_path` | `/etc/systemd/system/glances.service.d/piserv-api.conf` | PiServ-managed systemd override path |
| `base_glances_bind_address` | `127.0.0.1` | Loopback or wildcard IPv4 API listener |
| `base_glances_validation_address` | `127.0.0.1` | Loopback address used for API validation |
| `base_glances_port` | `61208` | Local Glances API port |
| `base_glances_auth_username` | `glances` | HTTP Basic username for the API |
| `base_glances_config_path` | `/etc/glances/glances.conf` | Configuration file that declares password-hash storage |
| `base_glances_password_directory` | `/etc/glances` | Directory containing the salted API password hash |
| `base_glances_bootstrap_password_file` | `/etc/glances/piserv-glances-bootstrap-password` | Root-only initial password for Home Assistant setup |
| `base_glances_state_directory` | `glances` | Dynamic-user state directory name |
| `base_glances_runtime_directory` | `glances` | Dynamic-user runtime directory name |
| `base_manage_cockpit` | `true` | Install and manage the Cockpit web console |
| `base_cockpit_packages` | `cockpit` | Cockpit package set installed without recommendations |
| `base_cockpit_expected_modules` | `[]` | Cockpit bridge package IDs asserted during live validation |
| `base_cockpit_socket_name` | `cockpit.socket` | Socket-activated Cockpit HTTPS unit |
| `base_cockpit_port` | `9090` | Cockpit HTTPS port |
| `base_manage_disabled_services` | `true` | Disable selected systemd units |
| `base_disabled_systemd_units` | CUPS, `rpcbind`, NFS block mapper | Units disabled when present |
| `base_manage_unattended_upgrades` | `true` | Manage unattended upgrades |
| `base_unattended_automatic_reboot_time` | `06:30` | Reboot window used only when upgrades require reboot |
| `base_unattended_origins_patterns` | Debian and Raspberry Pi origins | Allowed unattended-upgrades origins |
| `base_manage_unattended_upgrade_digest` | `true` | Send the PiServ mobile digest instead of native raw mail |
| `base_unattended_mail_to` | `root` | Recipient for both the digest and native error fallback |
| `base_unattended_mail_report` | `on-change` | Native-mail report mode when the digest is disabled |
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
Automatic reboot is enabled only for upgrades that require a reboot. The default
PiServ plugin sends a compact multipart email to local recipient `root`, with
old and installed package versions, reboot state, and no raw log transcript.
The full logs remain on PiServ under `/var/log/unattended-upgrades/`. Set
`base_manage_unattended_upgrade_digest: false` to restore the native report.
Native mail remains enabled for errors only, including unexpected failures that
cannot reach the plugin. Set `base_unattended_mail_to` to the required local
recipient for both paths, or leave it empty to disable unattended-upgrades mail.

The boot notification service is enabled by default, but systemd skips it until
`base_reboot_notification_condition_path` exists. Configure a mail transport
with a separate role before expecting delivery.

Glances uses the Debian package service with a PiServ-managed drop-in. The role
keeps its safe loopback default, while the PiServ playbook binds the JSON API to
IPv4 for LAN observability and Home Assistant. It enables HTTP Basic
authentication with a salted password hash and creates a root-only bootstrap
password alongside it. If either credential file is missing, the role rotates
both files so their values cannot remain inconsistent after an interrupted run.
The role creates a missing configured drop-in parent but preserves the metadata
of an existing system directory. The web UI stays disabled, and the dynamic
systemd user and service sandboxing remain in effect. The firewall permits the
current IPv4 LAN, while the existing Tailscale interface policy and tailnet ACLs
govern tailnet access. The role verifies that anonymous requests receive `401`,
tests the reconciled bootstrap credentials, and asserts the configured IPv4
listener without an IPv6 wildcard.

Cockpit is installed without its optional storage, NetworkManager, and package
management modules by default. The PiServ base playbook overrides
`base_cockpit_packages` to add `cockpit-storaged`, `cockpit-sosreport`, and
`cockpit-packagekit`. Its socket-activated HTTPS console listens on port `9090`,
uses the host PAM policy, and is reachable only after the project firewall
allows the required network path. The role verifies its local HTTPS login page
but does not manage browser credentials or certificates.

Cloud-init is disabled with `/etc/cloud/cloud-init.disabled`; the package is not
removed.

The Raspberry Pi OS VNC startup path is left unchanged. A PiServ oneshot runs
after `wayvnc-control.service` starts and selects `DSI-1`, the attached
4.3-inch touchscreen, instead of the first output selected by the vendor
control service. The selector is also started when either VNC service restarts.
Its parent directory must be root-owned and not writable by group or other
users; an absent parent is created as `root:root` with mode `0755`.
When the selector unit changes, the role runs `systemctl reenable` to reconcile
its installation links for both vendor VNC services without restarting WayVNC.
It also repairs a missing selector installation link on later runs.

## Validation

```sh
python3 tests/test_unattended_upgrade_digest.py
ansible-playbook tests/test-unattended-upgrades.yml
ANSIBLE_ROLES_PATH=.. ansible-playbook --syntax-check tests/test.yml
ansible-lint ansible/playbooks/piserv-base.yml ansible/roles/base
```
