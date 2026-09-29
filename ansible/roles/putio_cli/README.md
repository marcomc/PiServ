# Ansible Role: putio_cli

Build and install the official [putio-cli](https://github.com/putdotio/putio-cli)
from a pinned source release, including targets without an upstream prebuilt
binary such as Linux ARM64.

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Role Variables](#role-variables)
- [Example Playbook](#example-playbook)
- [Behavior](#behavior)
- [Validation](#validation)
- [License](#license)

## Requirements

| Requirement | Value |
| --- | --- |
| Target OS | Linux on ARM64 or x86_64 |
| Ansible | `ansible-core >= 2.15` |
| Privilege escalation | Required |
| Network | GitHub and nodejs.org |

The role builds the official CLI on the target using the pinned Node.js and
pnpm versions, installs dependencies from the committed lockfile, and runs
the upstream SEA verifier. It does not manage put.io credentials or perform
login.

## Installation

This role is not published to Ansible Galaxy yet. After its standalone role
repository is created and a release is imported, install it with:

```sh
ansible-galaxy role install marcomc.putio_cli,0.1.0
```

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `putio_cli_state` | `present` | Install or remove the CLI |
| `putio_cli_runtime_user` | Remote Ansible user | Owns the temporary source/build tree |
| `putio_cli_runtime_group` | Same as runtime user | Group for the source/build tree; override for shared primary groups |
| `putio_cli_runtime_user_home` | `/home/<runtime user>` (`/root` for root) | Home used for package-manager state; override for nonstandard homes |
| `putio_cli_repo_version` | `v1.6.2` | Official putio-cli Git ref |
| `putio_cli_expected_version` | Derived from the SemVer ref | Optional reported-version override for non-tag refs |
| `putio_cli_node_version` | `24.18.0` | Pinned official Node.js build runtime |
| `putio_cli_pnpm_version` | `11.2.2` | Pinned package manager |
| `putio_cli_source_dir` | `/opt/putio-cli` | Source and build directory |
| `putio_cli_node_install_root` | `/opt/nodejs` | Parent for the role's versioned Node.js runtime |
| `putio_cli_command_path` | `/usr/local/bin/putio` | Installed command path |

## Example Playbook

```yaml
---
- name: Install putio-cli
  hosts: download_hosts
  become: true
  roles:
    - role: marcomc.putio_cli
      vars:
        putio_cli_runtime_user: downloader
        putio_cli_repo_version: v1.6.2
```

## Behavior

The role verifies the Node.js archive against the checksum manifest published
by nodejs.org, builds the official source release, and installs the resulting
standalone executable. It never creates or copies an authentication token.
Missing source and command parent directories are created as needed; existing
source-parent metadata is preserved. An existing `putio_cli_node_install_root`
must be a non-symlink, root-owned directory with mode `0755`; unsafe or
unexpected existing roots are rejected without changing their metadata.

`state: absent` removes the installed command, source tree, and the Node.js
runtime directory for the configured Node.js version and architecture. Other
versions under `putio_cli_node_install_root` remain untouched. It does not
remove put.io user configuration.

## Validation

```sh
ansible-playbook -i tests/inventory tests/test.yml
ansible-playbook -i tests/inventory --syntax-check tests/test.yml
ansible-lint .
```

The cleanup test runs on Linux and requires privilege escalation. It is skipped
on non-Linux control or test hosts.

To exercise a fresh source build on Linux ARM64 or x86_64, run
`ansible-playbook -i <linux-inventory> tests/install.yml`. The test uses a
private temporary root on the target and removes it after validation; privilege
escalation and network access are required.

The role validates `putio version` after installation. Authentication and
account data remain operator actions outside Ansible.

## License

MIT. See [LICENSE](LICENSE).
