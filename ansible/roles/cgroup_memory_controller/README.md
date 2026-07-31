# Ansible Role: cgroup_memory_controller

Enable the cgroup v2 memory controller on Debian-family firmware hosts through
a validated Device Tree overlay.

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

This role manages a Device Tree overlay that removes exactly one configured
boot argument from `/chosen/bootargs`. It is intended for firmware where that
argument disables the cgroup v2 memory controller.

## Requirements

| Requirement | Value |
| --- | --- |
| Runtime precondition | Debian-family Linux with a Device Tree firmware boot path |
| Required input | Active vendor DTB path supplied by the consumer |
| Live-tested OS | Raspberry Pi OS Trixie |
| Ansible | `ansible-core >= 2.15` |
| Privilege escalation | Required |
| Facts | `gather_facts: true` |

## Installation

After the role is published to Ansible Galaxy:

```sh
ansible-galaxy role install marcomc.cgroup_memory_controller
```

Pinned install example:

```sh
ansible-galaxy role install marcomc.cgroup_memory_controller,0.1.0
```

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `cgroup_memory_controller_manage` | `true` | Enable role management; useful for a syntax-only consumer test |
| `cgroup_memory_controller_enabled` | `true` | Install the overlay; set `false` for rollback |
| `cgroup_memory_controller_vendor_dtb` | `""` | Required active vendor DTB source |
| `cgroup_memory_controller_config_path` | `/boot/firmware/config.txt` | Firmware configuration file |
| `cgroup_memory_controller_overlay_name` | `ansible-enable-cgroup-memory` | Managed overlay name |
| `cgroup_memory_controller_overlay_path` | Firmware overlay directory | Generated overlay destination |
| `cgroup_memory_controller_disabled_argument` | `cgroup_disable=memory` | Exact vendor boot argument to remove |
| `cgroup_memory_controller_helper_path` | `/usr/local/libexec/cgroup-memory-controller/...` | Generation and rollback helper |
| `cgroup_memory_controller_kernel_hook_path` | `/etc/kernel/postinst.d/zz-ansible-cgroup-memory-controller` | Overlay refresh hook |
| `cgroup_memory_controller_kernel_refresh_dependency_path` | `""` | Optional earlier hook that copies the vendor DTB |
| `cgroup_memory_controller_backup_dir` | `/var/lib/ansible/cgroup-memory-controller` | Root-only initial backup and source state |
| `cgroup_memory_controller_config_backup_filename` | `config.before-...` | Initial firmware configuration backup basename |
| `cgroup_memory_controller_vendor_dtb_backup_filename` | `vendor.dtb.before-...` | Initial vendor DTB backup basename |
| `cgroup_memory_controller_config_marker` | Ansible cgroup marker | Managed configuration block marker |
| `cgroup_memory_controller_require_runtime` | `false` | Require the active memory controller after reboot |
| `cgroup_memory_controller_runtime_systemd_service` | `""` | Optional service that must expose `memory.events` |

See `defaults/main.yml` for the complete defaults.

## Example Playbook

```yaml
---
- name: Enable cgroup v2 memory control on a firmware host
  hosts: firmware_hosts
  gather_facts: true
  roles:
    - role: marcomc.cgroup_memory_controller
      vars:
        cgroup_memory_controller_vendor_dtb: /boot/firmware/example-board.dtb
        cgroup_memory_controller_kernel_refresh_dependency_path: >-
          /etc/kernel/postinst.d/z50-firmware-copy
        cgroup_memory_controller_runtime_systemd_service: docker.service
```

## Supported Platforms

| Platform | Status |
| --- | --- |
| Raspberry Pi OS Trixie | Tested live with consumer-supplied paths |
| Debian 13 Trixie | Declared in Galaxy metadata; independent live validation pending |

## Behavior

The role installs `device-tree-compiler`, reads the configured DTB, and fails
unless the configured disabled argument occurs exactly once. It builds an
overlay that replaces `/chosen/bootargs`, validates the merged DTB offline, and
then enables the overlay through a marked firmware configuration block. Vendor
files are not modified.

The first normal run records copies of the firmware configuration and source
DTB in a root-only backup directory. The helper’s `--disable` mode removes only
the managed configuration block and overlay, retaining vendor updates and the
backup for comparison.

The optional kernel-refresh dependency lets a consumer declare the hook that
copies a new DTB into the boot filesystem. The role requires it to exist and to
sort before its own `zz-` hook. On each kernel update, the managed hook rebuilds
the overlay from the current vendor DTB. It removes the overlay if the argument
is no longer present; if validation fails, it removes the overlay and fails the
package operation rather than leaving stale boot arguments active.

The role never reboots the host. After an operator-approved reboot, set
`cgroup_memory_controller_require_runtime: true` to assert `memory` in the root
cgroup controller list. Set `cgroup_memory_controller_runtime_systemd_service`
to additionally require that service’s `memory.events` file.

## Task Layout

`tasks/main.yml` orchestrates the role. Scoped implementation lives in:

| File | Scope |
| --- | --- |
| `validate-target.yml` | Debian-family target assertion |
| `configuration.yml` | Overlay generation, rollback, kernel hook, and runtime checks |
| `enable-cgroup-memory-overlay.sh.j2` | Root-owned preflight, generation, and disable helper |
| `cgroup-memory-controller-kernel-hook.sh.j2` | Kernel post-install refresh entry point |

## Validation

Run from the role root without relying on a parent monorepo role path:

```sh
role_root=$(pwd)
tmp_dir=$(mktemp -d)
mkdir -p "$tmp_dir/roles"
ln -s "$role_root" "$tmp_dir/roles/cgroup_memory_controller"
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook --syntax-check tests/test.yml
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook tests/test-rendered-helpers.yml
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-lint .
rm -rf "$tmp_dir"
```

## Release Notes

See [CHANGELOG.md](CHANGELOG.md). Publication steps are documented in
[docs/releasing.md](docs/releasing.md).

## License

MIT. See [LICENSE](LICENSE).

## Support

Use the standalone role repository issue tracker after publication. Until then,
maintain the role alongside its consumer project.
