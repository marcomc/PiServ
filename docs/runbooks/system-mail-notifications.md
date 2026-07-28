# System Mail Notifications Runbook

## Table of Contents

- [Purpose](#purpose)
- [Status](#status)
- [Automation](#automation)
- [Gmail App Password](#gmail-app-password)
- [Manual Config](#manual-config)
- [Validation](#validation)
- [RaiPlaySound](#raiplaysound)
- [Rollback](#rollback)
- [Evidence Log](#evidence-log)

## Purpose

Configure PiServ host notifications through system mail without storing SMTP
account credentials in Ansible or this repository.

## Status

Applied on PiServ on 2026-07-08. The dedicated `msmtp` role installs the mail
packages and hardens operator-created file metadata without creating or owning
SMTP credentials. PiServ's playbook preserves operator edits to the SMTP sender,
user, password, and aliases. For Gmail SMTP, use a Gmail app password rather
than the normal account password or the Mac-specific OAuth helper. Provider
connectivity and one root-alias delivery test have been validated.

## Automation

The dedicated `msmtp` role installs:

| Package | Purpose |
| --- | --- |
| `msmtp` | SMTP client |
| `msmtp-mta` | `/usr/sbin/sendmail` compatibility |
| `bsd-mailx` | Manual mail testing utility |

The `msmtp` role configures:

| Area | Value |
| --- | --- |
| config mode | `unmanaged` for PiServ |
| aliases mode | `unmanaged` for PiServ |
| empty bootstrap | not created by Ansible |
| config metadata | `/etc/msmtprc` as `0640 root:msmtp` when present |
| binary metadata | `/usr/bin/msmtp` as `2755 root:msmtp` |
| compatibility wrapper | `/usr/local/bin/msmtp-system` |

The `base` role configures mail consumers:

| Area | Value |
| --- | --- |
| unattended-upgrades recipient | `base_unattended_mail_to` (default: `root`) for the plugin and native fallback |
| unattended-upgrades content | Mobile digest with package version transitions and plain-text fallback |
| unattended-upgrades full log | Retained at `/var/log/unattended-upgrades/` |
| unattended-upgrades failure | Native error-only mail fallback |
| boot notification service | `piserv-reboot-notify.service` |
| boot notification recipient | `root` |
| boot notification condition | skip until `/etc/msmtprc` exists and is non-empty |

## Gmail App Password

Use this path when the SMTP sender is Gmail.

Google's app-password flow is documented at
[Sign in with app passwords](https://support.google.com/accounts/answer/185833?hl=en).
Current Google requirements and limitations:

| Item | Meaning |
| --- | --- |
| 2-Step Verification | Required before app passwords can be created |
| Security-key-only 2-Step Verification | App passwords may be unavailable |
| Work, school, or organization account | App passwords may be unavailable |
| Advanced Protection | App passwords may be unavailable |
| Google account password change | Existing app passwords are revoked |

Create one app password dedicated to PiServ, for example named
`PiServ msmtp`. Google shows the generated password only once. Paste it only
into `/etc/msmtprc` on PiServ.

Do not use the normal Gmail password in `/etc/msmtprc`.

## Manual Config

Install the mail packages and hardening policy first:

```sh
ansible-playbook ansible/playbooks/piserv-base.yml
ssh admin@PiServ.local
sudo nano /etc/msmtprc
```

Use this shape, replacing the SMTP values:

```text
defaults
auth on
tls on
tls_starttls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
syslog on
aliases /etc/aliases
domain PiServ.local
auto_from off
allow_from_override off
set_from_header on

account default
host smtp.gmail.com
port 587
from your-gmail-address
user your-gmail-address
password gmail-app-password-here
```

Use the full Gmail address for both `from` and `user`. If Google displays the
app password grouped with spaces, remove the spaces when pasting it.

`domain PiServ.local` identifies PiServ in the SMTP handshake. `auto_from off`
keeps `msmtp` from generating sender addresses such as `root@PiServ.local`.
`allow_from_override off` and `set_from_header on` keep the configured sender
authoritative even when callers provide their own local `From` header.

Map local system mail to the external recipient:

```sh
sudo nano /etc/aliases
```

Example shape:

```text
root: operator@example.com
default: operator@example.com
```

Keep `/etc/msmtprc` only on PiServ. Do not commit it or copy it into this repo.

Do not validate as `admin` with `msmtp --file /etc/msmtprc`; explicit `--file`
treats the file as caller-owned config and fails when the system config is
root-owned. Use the default system config path instead.

## Validation

Stop here until the manual config exists and is non-empty.

After `/etc/msmtprc` is configured, run the base playbook. The playbook applies
the dedicated `msmtp` role before the `base` role:

```sh
ansible-playbook ansible/playbooks/piserv-base.yml
```

Then validate the system config path:

```sh
ssh admin@PiServ.local 'timeout 30 msmtp --serverinfo'
ssh admin@PiServ.local 'timeout 30 /usr/local/bin/msmtp-system --file /etc/msmtprc --serverinfo'
ssh admin@PiServ.local 'stat -c "%a %U %G %n" /etc/msmtprc /usr/bin/msmtp'
```

Expected metadata:

```text
640 root msmtp /etc/msmtprc
644 root root /etc/aliases
2755 root msmtp /usr/bin/msmtp
755 root root /usr/local/bin/msmtp-system
```

Validate mail delivery only when ready to send a test message:

```sh
ssh admin@PiServ.local 'printf "PiServ mail test\n" | mail -s "PiServ mail test" root'
```

Verify:

```sh
ssh admin@PiServ.local 'systemctl status piserv-reboot-notify.service --no-pager'
ssh admin@PiServ.local 'sudo test -f /etc/unattended-upgrades/plugins/UnattendedUpgradesPluginPiServMail.py'
ssh admin@PiServ.local 'sudo grep -R "^Unattended-Upgrade::Mail" -n /etc/apt/apt.conf.d'
```

When the digest plugin is enabled, the third command shows `MailReport
"only-on-error"`: the plugin sends routine messages and native mail preserves
an unexpected-failure fallback. Routine messages show status, reboot state,
held packages, and each package's `previous -> installed` version. Full
package-manager logs remain on PiServ. Error fallback messages use the native
raw format so an unexpected failure cannot be silent.

## RaiPlaySound

The playbook now creates new RaiPlaySound configs with:

```text
EMAIL_TO="root"
EMAIL_CONFIG="/etc/msmtprc"
EMAIL_FROM="operator@example.com"
EMAIL_FROM_NAME="PiServ RaiPlaySound"
EMAIL_SUBJECT_PREFIX="[PiServ raiplaysound-cli]"
MSMTP_BIN="/usr/local/bin/msmtp-system"
```

The live PiServ config is create-only and already has these keys.

## Rollback

Disable boot notifications:

```sh
ssh admin@PiServ.local 'sudo systemctl disable --now piserv-reboot-notify.service'
```

Remove email keys from the RaiPlaySound config to make it skip summaries again.

## Evidence Log

| Date | Check | Result |
| --- | --- | --- |
| 2026-07-08 | Galaxy role assessment | `fauch922.ansible_msmtp_setup` selected as local-fork inspiration |
| 2026-07-08 | unattended-upgrades option check | Installed config confirms `Mail` and `MailReport "on-change"` |
| 2026-07-08 | `/etc/msmtprc` ownership check | `admin` must not use explicit `--file`; use the system config path or wrapper |
| 2026-07-08 | Initial base playbook apply | Added statoverride, wrapper, and `0640 root:msmtp` config metadata |
| 2026-07-08 | Server-info validation | `msmtp --serverinfo` and wrapper server-info both returned `0` |
| 2026-07-08 | Envelope controls | Added `allow_from_override off` and `set_from_header on` manually |
| 2026-07-08 | Delivery validation | `mail -s ... root` delivered through the root alias |
| 2026-07-08 | Role split | Mail transport moved to the dedicated local `msmtp` role |
| 2026-07-08 | Final base playbook apply | Create-only `msmtp` role and `base` role completed with `changed=0` |
| 2026-07-16 | Mobile upgrade digest | Plugin installed, routine raw mail removed, dry run passed, and test digest delivered through the root alias |
