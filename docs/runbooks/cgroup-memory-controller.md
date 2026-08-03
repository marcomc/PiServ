# Cgroup Memory Controller

## Table of Contents

- [Purpose](#purpose)
- [Managed State](#managed-state)
- [Apply and Preflight](#apply-and-preflight)
- [Activation and Runtime Validation](#activation-and-runtime-validation)
- [Rollback](#rollback)
- [Kernel Updates and Recovery](#kernel-updates-and-recovery)

## Purpose

Enable the cgroup v2 memory controller on PiServ without changing the vendor
Device Tree Blob (DTB). This makes the existing systemd and Docker memory
limits enforceable for Hermes local-model services and future bounded workloads.

The current Pi 5 DTB puts `cgroup_disable=memory` in `/chosen/bootargs`.
An overlay cannot remove it because Raspberry Pi firmware
[`bootargs` assignments append instead of overwrite][rpi-bootargs]. PiServ
therefore boots a validated, managed copy of the complete vendor DTB.

[rpi-bootargs]: https://www.raspberrypi.com/documentation/computers/configuration.html#special-properties

## Managed State

The reusable `cgroup_memory_controller` role manages these artifacts through
PiServ consumer values:

| Path | Purpose |
| --- | --- |
| `/boot/firmware/piserv-cgroup-memory.dtb` | PiServ-owned full copy generated from the installed vendor DTB |
| `/boot/firmware/config.txt` | A marked `[all]` and `device_tree=piserv-cgroup-memory.dtb` block |
| `/usr/local/libexec/piserv/manage-cgroup-memory-dtb` | Root-owned preflight, generation, validation, and disable helper |
| `/etc/kernel/postinst.d/zz-piserv-cgroup-memory-controller` | Refreshes the managed DTB after Raspberry Pi's firmware-copy hook |
| `/var/lib/piserv/boot-backups/cgroup-memory-controller` | Root-only initial boot-artifact backups, SHA-256 manifest, and current source state |

The helper copies the complete vendor DTB, removes exactly one
`cgroup_disable=memory` token with `fdtput`, and validates with `fdtget` that the
managed `bootargs` match the vendor arguments except for that token.
Before each apply, it also revalidates the retained backups and requires a
root-owned vendor DTB that is not writable by unprivileged users. The helper
also revalidates the firmware-refresh dependency, keeps its managed selection
last in `config.txt`, verifies the active `cold` reboot mode before apply, and
atomically refreshes `current-source-state`.
The role creates `backup-checksums.sha256` only with a fresh pair of backups;
partial or unmanifested existing sets fail without being modified.
Rollback also validates this recovery set before changing boot state.

## Apply and Preflight

Apply the role without restarting PiServ:

```sh
ansible-playbook ansible/playbooks/piserv-base.yml
ssh admin@PiServ.local \
  'sudo /usr/local/libexec/piserv/manage-cgroup-memory-dtb --check'
ssh admin@PiServ.local \
  "sudo grep -A2 -B1 'PiServ cgroup v2 memory controller' /boot/firmware/config.txt"
```

Observed on PiServ after the 2026-08-03 deployment:

```text
status=managed-dtb-required
changed=false
source_dtb_sha256=4186c583885d0337494d9c8e4533a2d387e948ac00c2e4ae4c7e12b5c49ebe35
reboot_mode=cold
```

Before adding the manifest, the retained configuration matched a reconstruction
of the pre-managed `config.txt` byte-for-byte and `fdtget` parsed the retained
vendor DTB. The migrated manifest then passed normal and check-mode role runs.
The independently invoked installed kernel hook returned the same idempotent
status while the active reboot mode was `cold`.

`changed=false` proves the installed managed DTB matches the current vendor DTB
and the marked firmware selection is correct.
The live controller list was `cpuset cpu io pids`, so `memory` is not active.
No reboot was performed; the follow-up remains an operator-approved reboot and
the runtime validation below.

## Activation and Runtime Validation

Schedule and perform an operator-approved reboot. The role never triggers it.

```sh
ssh admin@PiServ.local 'sudo systemctl reboot'
```

After PiServ is reachable again, validate the active controller and Docker
cgroup files through the role:

```sh
ansible-playbook ansible/playbooks/piserv-base.yml \
  -e cgroup_memory_controller_require_runtime=true
ssh admin@PiServ.local 'cat /sys/fs/cgroup/cgroup.controllers'
ssh admin@PiServ.local \
  'sudo systemctl show docker.service --property=ControlGroup --value'
```

The controller list must include `memory`; the role also requires a readable
`memory.events` file under Docker's service cgroup. Keep Hermes `LimitAS=4G`
in place while recording real limits and memory pressure before another full
64K local-provider test.

## Rollback

Remove only the PiServ-managed configuration, preserving the current vendor
DTB and all unrelated firmware configuration:

```sh
ansible-playbook ansible/playbooks/piserv-base.yml \
  -e cgroup_memory_controller_enabled=false
ssh admin@PiServ.local 'sudo systemctl reboot'
```

After restart, `memory` should no longer appear in
`/sys/fs/cgroup/cgroup.controllers` on the current vendor firmware. The backup
directory is for audit and emergency comparison; do not restore an old whole
`config.txt` or DTB over newer vendor firmware as normal rollback.

## Kernel Updates and Recovery

Raspberry Pi's `z50-raspi-firmware` kernel post-install hook copies the current
DTB to `/boot/firmware`. PiServ's `zz-piserv-cgroup-memory-controller` hook
runs afterwards, revalidates that earlier hook, regenerates the managed DTB
from the new vendor DTB, and refreshes the recorded source checksum.

If the vendor DTB already omits `cgroup_disable=memory`, the hook removes the
redundant managed DTB and configuration block. If the DTB is malformed,
ambiguous, or cannot pass `fdtget` validation, the hook attempts to remove the
managed selection and DTB, then fails the package operation visibly.

If rollback itself fails, the hook reports that the managed state could not be
disabled. Do not reboot until the helper's `--check` output and the marked
firmware block have been inspected and corrected.

Recover by inspecting the package failure and the source state, then rerunning
the base playbook after correcting the cause:

```sh
ssh admin@PiServ.local \
  'sudo cat /var/lib/piserv/boot-backups/cgroup-memory-controller/current-source-state'
ssh admin@PiServ.local \
  'sudo /usr/local/libexec/piserv/manage-cgroup-memory-dtb --check'
ansible-playbook ansible/playbooks/piserv-base.yml
```
