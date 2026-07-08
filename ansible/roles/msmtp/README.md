# Ansible Role: msmtp

Install and configure `msmtp` with explicit support for fully managed,
create-only, or operator-managed configuration.

## Table of Contents

- [Purpose](#purpose)
- [Requirements](#requirements)
- [Installation](#installation)
- [Role Variables](#role-variables)
- [Example Playbook](#example-playbook)
- [Supported Platforms](#supported-platforms)
- [Behavior](#behavior)
- [Validation](#validation)
- [Release Notes](#release-notes)
- [License](#license)
- [Support](#support)

## Purpose

This role installs `msmtp` and can either own the mail configuration or leave
SMTP credentials under operator control.

It supports:

- package installation
- `msmtp` group creation
- optional `/etc/msmtprc` rendering
- optional `/etc/aliases` rendering
- existing config metadata hardening
- `dpkg-statoverride` for setgid system-config access
- an optional compatibility wrapper for callers that pass `/etc/msmtprc` with
  explicit `--file`

The account and alias model is inspired by
`fauch922.ansible_msmtp_setup`, with additional management-mode and hardening
controls.

## Requirements

| Requirement | Value |
| --- | --- |
| Target OS | Debian-family Linux |
| Tested OS | Raspberry Pi OS Trixie |
| Ansible | `ansible-core >= 2.15` |
| Privilege escalation | Required |
| Network | Target must reach Debian package repositories |

## Installation

After the role is published to Ansible Galaxy:

```sh
ansible-galaxy role install marcomc.msmtp
```

Pinned install example:

```sh
ansible-galaxy role install marcomc.msmtp,0.1.0
```

Standalone role syntax validation:

```sh
ansible-playbook --syntax-check tests/test.yml
```

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `msmtp_manage_packages` | `true` | Install `msmtp` packages |
| `msmtp_packages` | `msmtp`, `msmtp-mta`, `bsd-mailx` | Package list |
| `msmtp_manage_group` | `true` | Create the `msmtp` group |
| `msmtp_group` | `msmtp` | Group used for system config access |
| `msmtp_manage_binary_statoverride` | `true` | Persist setgid binary metadata |
| `msmtp_binary_path` | `/usr/bin/msmtp` | msmtp binary path |
| `msmtp_binary_mode` | `2755` | msmtp binary mode |
| `msmtp_config_path` | `/etc/msmtprc` | System msmtp config path |
| `msmtp_config_management` | `unmanaged` | Config mode: `managed`, `create`, or `unmanaged` |
| `msmtp_config_mode` | `0640` | Config mode when written or hardened |
| `msmtp_harden_existing_config` | `true` | Harden config metadata when the file exists |
| `msmtp_config_required` | `false` | Fail when the config is missing |
| `msmtp_aliases_path` | `/etc/aliases` | msmtp aliases path |
| `msmtp_aliases_management` | `unmanaged` | Aliases mode: `managed`, `create`, or `unmanaged` |
| `msmtp_harden_existing_aliases` | `true` | Harden aliases metadata when the file exists |
| `msmtp_manage_compat_wrapper` | `false` | Install compatibility wrapper |
| `msmtp_compat_wrapper_path` | `/usr/local/bin/msmtp-system` | Compatibility wrapper path |
| `msmtp_global_settings` | See `defaults/main.yml` | Global `defaults` settings |
| `msmtp_accounts` | `[]` | Account definitions |
| `msmtp_default_account` | `""` | Default account name |
| `msmtp_aliases` | `{}` | Alias mapping or list of user/mail dictionaries |
| `msmtp_alias_default` | `""` | Default alias target |

## Example Playbook

Operator-managed secrets:

```yaml
---
- name: Install msmtp and preserve local config
  hosts: all
  roles:
    - role: marcomc.msmtp
      vars:
        msmtp_config_management: unmanaged
        msmtp_aliases_management: unmanaged
        msmtp_harden_existing_config: true
        msmtp_manage_compat_wrapper: true
```

Create files only when missing:

```yaml
---
- name: Bootstrap msmtp config
  hosts: all
  roles:
    - role: marcomc.msmtp
      vars:
        msmtp_config_management: create
        msmtp_aliases_management: create
        msmtp_default_account: gmail
        msmtp_accounts:
          - name: gmail
            host: smtp.gmail.com
            port: 587
            from: operator@example.com
            user: operator@example.com
            password: "{{ vault_gmail_app_password }}"
        msmtp_aliases:
          root: operator@example.com
```

Fully managed config:

```yaml
---
- name: Manage msmtp config from Ansible
  hosts: all
  roles:
    - role: marcomc.msmtp
      vars:
        msmtp_config_management: managed
        msmtp_aliases_management: managed
        msmtp_default_account: gmail
        msmtp_accounts:
          - name: gmail
            host: smtp.gmail.com
            port: 587
            from: operator@example.com
            user: operator@example.com
            passwordeval: "pass show smtp/gmail"
        msmtp_aliases:
          root: operator@example.com
          default: operator@example.com
```

## Supported Platforms

| Platform | Status |
| --- | --- |
| Debian 13 / Raspberry Pi OS Trixie | Tested |
| Debian 12 / Raspberry Pi OS Bookworm | Metadata-supported, not yet live-tested |

## Behavior

`msmtp_config_management` controls `/etc/msmtprc`:

| Mode | Behavior |
| --- | --- |
| `managed` | Always render the config from role variables |
| `create` | Render the config only when missing |
| `unmanaged` | Never render the config |

`msmtp_aliases_management` applies the same model to aliases.

When `msmtp_harden_existing_config` is true, the role applies
`0640 root:msmtp` metadata to an existing config even in `unmanaged` mode. This
lets operators keep SMTP credentials on the host while Ansible still enforces
safe file metadata.

The compatibility wrapper strips `--file {{ msmtp_config_path }}` before
executing `msmtp`. It is useful for tools that insist on passing the system
config as an explicit file even though `msmtp` expects explicit config files to
be owned by the caller.

## Validation

```sh
ANSIBLE_ROLES_PATH=.. ansible-playbook --syntax-check tests/test.yml
ansible-lint .
```

## Release Notes

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT.

## Support

Open issues against the standalone role repository after publication. Until
then, treat this role as a local project role.
