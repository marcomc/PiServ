# Ansible Role: journald

Configure systemd-journald storage, retention, and disk-use policy on
Debian-family hosts.

## Table of Contents

- [Purpose](#purpose)
- [Requirements](#requirements)
- [Installation](#installation)
- [Role Variables](#role-variables)
- [Example Playbook](#example-playbook)
- [Supported Platforms](#supported-platforms)
- [Behavior](#behavior)
- [Task Layout](#task-layout)
- [Validation](#validation)
- [Release Notes](#release-notes)
- [License](#license)
- [Support](#support)

## Purpose

This role manages one journald drop-in and, after a change, restarts then
flushes journald so the active boot is written to the configured storage.

## Requirements

| Requirement | Value |
| --- | --- |
| Target OS | Debian-family Linux |
| Tested OS | Raspberry Pi OS Trixie |
| Ansible | `ansible-core >= 2.15` |
| Privilege escalation | Required |
| Facts | `gather_facts: true` |

## Installation

After the role is published to Ansible Galaxy:

```sh
ansible-galaxy role install marcomc.journald
```

Pinned install example:

```sh
ansible-galaxy role install marcomc.journald,0.1.0
```

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `journald_dropin_path` | `/etc/systemd/journald.conf.d/99-ansible-journald.conf` | Managed drop-in path |
| `journald_storage` | `persistent` | Storage mode: `auto`, `volatile`, or `persistent` |
| `journald_compress` | `true` | Compress persistent journal entries |
| `journald_system_max_use` | `""` | Optional total journal disk-use limit |
| `journald_system_keep_free` | `""` | Optional filesystem space reserve |
| `journald_system_max_file_size` | `""` | Optional per-file size limit |
| `journald_max_retention_sec` | `""` | Optional retention limit |
| `journald_sync_interval_sec` | `""` | Optional synchronization interval |

## Example Playbook

```yaml
---
- name: Configure persistent system journals
  hosts: debian_hosts
  gather_facts: true
  roles:
    - role: marcomc.journald
      vars:
        journald_storage: persistent
        journald_compress: true
        journald_system_max_use: 1G
        journald_system_keep_free: 5G
        journald_system_max_file_size: 128M
        journald_max_retention_sec: 14day
```

## Supported Platforms

| Platform | Status |
| --- | --- |
| Raspberry Pi OS Trixie | Tested live |
| Debian 13 Trixie | Metadata-supported and tested through Raspberry Pi OS |

## Behavior

The generic default policy sets persistent storage and compression. It leaves
resource limits, retention, and synchronization cadence at the systemd package
defaults until the consumer sets the corresponding optional variables.

The role validates the Debian operating-system family before changing the
target. It stats the drop-in parent and creates it only when missing; an
existing directory retains its ownership and mode. The managed drop-in is
`0644 root:root`.

On a changed drop-in, handlers run in order: systemd-journald restarts, then
`journalctl --flush` writes the current runtime journal to the configured
storage.

## Task Layout

`tasks/main.yml` is orchestration only. Scoped implementation lives in:

| File | Scope |
| --- | --- |
| `validate-target.yml` | Debian-family target assertion |
| `configuration.yml` | Parent inspection and drop-in rendering |

## Validation

Run from the role root without relying on a parent monorepo role path:

```sh
role_root=$(pwd)
tmp_dir=$(mktemp -d)
mkdir -p "$tmp_dir/roles"
ln -s "$role_root" "$tmp_dir/roles/journald"
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook --syntax-check tests/test.yml
rm -rf "$tmp_dir"
ansible-lint .
```

## Release Notes

See [CHANGELOG.md](CHANGELOG.md). Publication steps are documented in
[docs/releasing.md](docs/releasing.md).

## License

MIT. See [LICENSE](LICENSE).

## Support

Use the standalone role repository issue tracker after publication. Until then,
maintain the role alongside its consumer project.
