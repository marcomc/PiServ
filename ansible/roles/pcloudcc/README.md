# Ansible Role: pcloudcc

Build and install the official pCloud console client on Raspberry Pi OS or
Debian.

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

This role automates the validated pcloudcc installation path:

- install Debian build dependencies
- check out the official pCloud console-client source
- apply the Debian arm64 compatibility patch
- build the FUSE-enabled pcloudcc client
- install `pcloudcc` and its shared library under `/usr/local`
- prepare the pCloud mount root directory

The role intentionally stops before credential bootstrap and mount service
management. Use a separate runbook or role for interactive `pcloudcc -p -s`
login and systemd startup after live account validation.

## Requirements

| Requirement | Value |
| --- | --- |
| Target hardware | Raspberry Pi or Debian-compatible `arm64` host |
| Target OS | Debian-family OS |
| Tested OS | Debian 13 / Raspberry Pi OS Trixie |
| Ansible | `ansible-core >= 2.15` |
| Privilege escalation | Required |
| Network | Target must reach GitHub and Debian package repositories |

## Installation

After the role is published to Ansible Galaxy:

```sh
ansible-galaxy role install marcomc.pcloudcc
```

Pinned install example:

```sh
ansible-galaxy role install marcomc.pcloudcc,0.1.0
```

Standalone role syntax validation:

```sh
ansible-playbook --syntax-check tests/test.yml
```

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `pcloudcc_runtime_user` | Remote user fact or `root` fallback | User that owns the checkout and mount root |
| `pcloudcc_install_root` | `/opt/pcloudcc` | Parent directory for pcloudcc source |
| `pcloudcc_source_dir` | `/opt/pcloudcc/console-client` | Official source checkout path |
| `pcloudcc_repo_url` | pCloud console-client GitHub repository | Upstream source repository |
| `pcloudcc_repo_version` | `980d2cadf670f1b14642c7dbe015f95bd2306175` | pCloud source revision |
| `pcloudcc_version` | `2.0.1` | Expected pcloudcc client version after install |
| `pcloudcc_repo_update` | `false` | Fetch or refresh an existing checkout |
| `pcloudcc_repo_force` | `false` | Allow Git to discard local checkout changes during updates |
| `pcloudcc_mount_root` | `/mnt/pcloud` | Mount point prepared for later pcloudcc use |
| `pcloudcc_patch_file` | `pcloudcc-debian13-arm64.patch` | Debian arm64 source patch |
| `pcloudcc_force_rebuild` | `false` | Rebuild even when `pcloudcc` is installed |
| `pcloudcc_build_jobs` | CPU count or `2` | Parallel make job count |
| `pcloudcc_expected_version_output` | `pCloud console client v.{{ pcloudcc_version }}` | Expected help/version output |
| `pcloudcc_apt_packages` | See `defaults/main.yml` | Debian packages required to build pcloudcc |

## Example Playbook

```yaml
---
- name: Install pcloudcc
  hosts: raspberry_pi
  gather_facts: true
  roles:
    - role: marcomc.pcloudcc
```

Override the source checkout path:

```yaml
---
- name: Install pcloudcc under a custom source path
  hosts: raspberry_pi
  gather_facts: true
  roles:
    - role: marcomc.pcloudcc
      vars:
        pcloudcc_install_root: /srv/build/pcloudcc
        pcloudcc_mount_root: /mnt/pcloud
```

## Supported Platforms

| Platform | Status |
| --- | --- |
| Debian 13 / Raspberry Pi OS Trixie on Raspberry Pi 5 `arm64` | Tested |
| Debian 12 / Raspberry Pi OS Bookworm `arm64` | Metadata-supported, not yet live-tested |

## Behavior

The role pins the pCloud source revision validated for Debian 13 `arm64`.
Upstream Git updates are disabled by default after the initial clone so repeat
runs do not depend on GitHub availability.

`pcloudcc_version` is the expected installed client version. `pcloudcc_repo_version`
is the exact upstream Git ref used to build that client. When changing the
desired client version, update both values and set `pcloudcc_repo_update: true`
on hosts that already have a source checkout.

The role applies `files/pcloudcc-debian13-arm64.patch` because the official
source currently ships x86 tuning flags and legacy C constructs that Debian 13
GCC rejects on `arm64`.

The role does not configure a pCloud account email and does not store a pCloud
password. First login remains an operator action:

```sh
pcloudcc -u "PCLOUD_ACCOUNT_EMAIL" -p -s -m /mnt/pcloud
```

The role does not create a systemd unit. Add systemd management only after the
interactive credential bootstrap, EU-region login behavior, and mount recovery
have been validated on the target.

## Task Layout

`tasks/main.yml` is only an orchestrator. Scoped operations live in dedicated
task files:

| File | Scope |
| --- | --- |
| `validate-target.yml` | Debian-family `arm64` assertion |
| `packages.yml` | Build dependency packages |
| `source.yml` | Source checkout, patch application, and mount root |
| `build.yml` | pcloudcc build and install |
| `validate-install.yml` | Installed binary, library, and mount root validation |

## Validation

Role validation:

```sh
ansible-playbook --syntax-check tests/test.yml
ansible-lint .
```

Role validation after Galaxy-style export:

```sh
ansible-playbook --syntax-check tests/test.yml
```

Live idempotence validation used during development:

```text
ansible-playbook site.yml
ansible-playbook site.yml
```

The second run should report `changed=0`.

## Release Notes

See [CHANGELOG.md](CHANGELOG.md).

Publication steps are documented in [docs/releasing.md](docs/releasing.md).

## License

MIT. See [LICENSE](LICENSE).

This role clones pCloud's upstream repository and carries a small build patch,
but it does not vendor or redistribute the full pCloud source code in the
Galaxy role package.

## Support

Use the repository issue tracker after the standalone public role repository is
created. pCloud account, service, and product issues should be directed to
pCloud support.
