# 0008: System Mail Notifications

## Status

Accepted and implemented on 2026-07-08.

## Context

PiServ now owns scheduled podcast generation and should also report host-level
events such as unattended upgrades and reboots.

`raiplaysound-cli` can send summaries through `msmtp`, but the Mac `msmtp`
setup was independent of the CLI. PiServ needs a broader host-level mail path,
not only a user-scoped RaiPlaySound config.

Existing Galaxy roles were considered:

| Role | Fit | Reason |
| --- | --- | --- |
| `roots.msmtp` | Not selected | Good system role, but templates `/etc/msmtprc` from Ansible variables |
| `escalate.msmtp` | Not selected | Pi OS-oriented, but also manages `/etc/msmtprc` and aliases |
| `chriswayg.msmtp-mailer` | Not selected | Broader MTA role with managed account-secret model |
| `fauch922.ansible_msmtp_setup` | Fork inspiration | Closest fit, but still always owns `/etc/msmtprc` and `/etc/aliases` |

The chosen secret model is manual: the SMTP sender, user, and password live only
in `/etc/msmtprc` on PiServ, not in Ansible Vault and not in this repository.
For Gmail SMTP, use a dedicated Gmail app password in `/etc/msmtprc`. Avoid the
Mac-specific XOAUTH2 helper because it depends on macOS Keychain; a Linux OAuth
helper is unnecessary while Gmail app passwords are available for the account.

## Decision

Use a dedicated project-local `msmtp` role, inspired by
`fauch922.ansible_msmtp_setup`, for mail transport setup. The role supports
`managed`, `create`, and `unmanaged` modes for `/etc/msmtprc` and aliases.
PiServ uses `unmanaged` mode for those files because they contain credentials
and local delivery policy. The role installs packages, persists binary metadata,
and hardens operator-created files when present.

| Area | Decision |
| --- | --- |
| Role | Dedicated local `msmtp` role |
| Upstream source | Inspired by `Fauch922/ansible-msmtp-setup` commit `ad915e0a2162bf1fa7b77211f1392a8bc879c94b` |
| Config mode | `msmtp_config_management: unmanaged` |
| Aliases mode | `msmtp_aliases_management: unmanaged` |
| Empty bootstrap | Do not create empty mail config files |
| Packages | Install `msmtp`, `msmtp-mta`, and `bsd-mailx` |
| SMTP config | Operator-managed `/etc/msmtprc` |
| SMTP config metadata | Harden existing config to `0640 root:msmtp` |
| SMTP binary metadata | Persist `2755 root:msmtp` with `dpkg-statoverride` |
| Gmail auth | Dedicated app password |
| Envelope settings | Explicit `from`, `domain PiServ.local`, `auto_from off`, `set_from_header on` |
| Local recipient | Send to `root` |
| External recipient | Operator-managed aliases in `/etc/aliases` |
| unattended-upgrades | Mail `root`, report `on-change` |
| Boot notice | systemd oneshot, skipped until `/etc/msmtprc` exists and is non-empty |
| RaiPlaySound | Uses `/usr/local/bin/msmtp-system` for system-config compatibility |

Do not add an external Galaxy `msmtp` dependency unless PiServ later switches
to Ansible Vault-managed SMTP credentials or the local fork is published as a
standalone role.

## Consequences

- SMTP credentials are never stored in this repository.
- System services can use `/usr/sbin/sendmail` through `msmtp-mta`.
- Local users can send through the configured system mail path without reading
  `/etc/msmtprc`.
- Re-running Ansible will not create or overwrite `/etc/msmtprc` or
  `/etc/aliases`; it only hardens existing files.
- Commands run as `admin` should not pass `--file /etc/msmtprc` directly; use
  the default system config path or `/usr/local/bin/msmtp-system`.
- If the Google account password changes, the Gmail app password must be
  regenerated and updated on PiServ.
- SMTP provider connectivity and one root-alias delivery test have been
  validated.

## Validation

Current validation:

| Check | Expected result |
| --- | --- |
| `msmtp --serverinfo` | SMTP provider reachable through the system config |
| `/usr/local/bin/msmtp-system --file /etc/msmtprc --serverinfo` | Wrapper strips the explicit system-config file |
| `stat -c ... /etc/msmtprc /usr/bin/msmtp` | `0640 root:msmtp` config and `2755 root:msmtp` binary |
| `mail -s ... root` | External notification received through alias |
| PiServ base playbook | Unmanaged mail config mode validates and remains idempotent |
| `piserv-reboot-notify.service` | Sends a boot email after reboot when `/etc/msmtprc` is non-empty |
| unattended-upgrades | Sends reports when upgrades or errors occur |
| RaiPlaySound | Email configuration present; dry-run summary validation passed |
