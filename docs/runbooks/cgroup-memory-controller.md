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
Appending an argument in `cmdline.txt` does not undo that setting.

## Managed State

The reusable `cgroup_memory_controller` role manages these artifacts through
PiServ consumer values:

| Path | Purpose |
| --- | --- |
| `/boot/firmware/overlays/piserv-enable-cgroup-memory.dtbo` | PiServ-owned overlay generated from the installed vendor DTB |
| `/boot/firmware/config.txt` | A marked `dtoverlay=piserv-enable-cgroup-memory` entry |
| `/usr/local/libexec/piserv/enable-cgroup-memory-overlay` | Root-owned preflight, generation, validation, and disable helper |
| `/etc/kernel/postinst.d/zz-piserv-cgroup-memory-controller` | Refreshes the overlay after Raspberry Pi's firmware-copy hook |
| `/var/lib/piserv/boot-backups/cgroup-memory-controller` | Root-only initial boot-artifact backups and current source state |

The helper removes exactly one `cgroup_disable=memory` token, compiles an
overlay, merges it with the current DTB offline, and requires the merged
`bootargs` to match the vendor arguments except for that token.

## Apply and Preflight

Apply the role without restarting PiServ:

```sh
ansible-playbook ansible/playbooks/piserv-base.yml
ssh admin@PiServ.local \
  'sudo /usr/local/libexec/piserv/enable-cgroup-memory-overlay --check'
ssh admin@PiServ.local \
  "sudo grep -A2 -B1 'PiServ cgroup v2 memory controller' /boot/firmware/config.txt"
```

Expected preflight output before activation includes:

```text
status=overlay-required
changed=false
source_dtb_sha256=<current vendor DTB checksum>
```

`changed=false` proves the installed overlay matches the current vendor DTB.
The host still has no active memory controller until it is restarted.

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
runs afterwards and regenerates the overlay from that new DTB.

If the vendor DTB already omits `cgroup_disable=memory`, the hook removes the
redundant overlay and config block. If the DTB is malformed, ambiguous, or
cannot pass the offline merge, it removes the managed overlay and makes the
package operation fail visibly. This prevents a reboot with an overlay that
would replace newer vendor boot arguments.

Recover by inspecting the package failure and the source state, then rerunning
the base playbook after correcting the cause:

```sh
ssh admin@PiServ.local \
  'sudo cat /var/lib/piserv/boot-backups/cgroup-memory-controller/current-source-state'
ssh admin@PiServ.local \
  'sudo /usr/local/libexec/piserv/enable-cgroup-memory-overlay --check'
ansible-playbook ansible/playbooks/piserv-base.yml
```
