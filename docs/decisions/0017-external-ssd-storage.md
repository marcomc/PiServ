# 0017: PiServ External SSD Storage

## Table of Contents

- [Status](#status)
- [Context](#context)
- [Decision](#decision)
- [Permissions](#permissions)
- [Consequences](#consequences)
- [Validation](#validation)

## Status

Accepted and implemented on 2026-07-23.

## Context

PiServ received a 4 TB SSD in an ASMedia ASM246X USB enclosure. The disk was
originally GPT-partitioned with an EFI partition and two APFS partitions. APFS
does not provide the native Linux read/write service-storage path required by
PiServ.

The enclosure is connected through a Raspberry Pi 5 USB 3 port and negotiated
at 5 Gbps after the cable and port were corrected. The disk is owned by
PiServ; direct macOS access is not a requirement for this volume.

## Decision

- Erase the existing partition layout.
- Create one GPT partition spanning the disk.
- Format it as journaled ext4 with filesystem label `external-data`.
- Mount it at `/mnt/external-data` using the filesystem UUID in an `/etc/fstab`
  entry. The steady-state playbook discovers the partition by its unique
  `external-data` filesystem label and resolves the parent disk at runtime.
  It compares that disk's udev model and serial with the ignored local
  `ansible/vars/external-storage.yml` identity before any mutation. Stable by-id
  paths are not configuration inputs.
- Use `nodev` and `nosuid` mount options. `nofail` allows PiServ to boot when
  the removable disk is absent; services using the disk must declare their
  mount dependency explicitly.

The current disk identity is:

| Property | Value |
| --- | --- |
| Device identity | Runtime filesystem-label discovery plus ignored local udev model and serial verification |
| Filesystem UUID | Read at convergence and written to fstab |
| Mountpoint | `/mnt/external-data` |

## Permissions

The `external-data` group is the service write group. Future service accounts
must be added explicitly through `piserv_external_storage_service_users` rather
than to `admin` or `sudo`. The existing `admin` group receives a named write
ACL, so every human administrator gets access without granting service accounts
administrative privileges.

| Path | Owner and mode | Access |
| --- | --- | --- |
| `/mnt/external-data` | `root:external-data`, `2775` | All users read/traverse; `admin` and service group write |
| `/mnt/external-data/shared` | `root:external-data`, `2775` | Shared user-readable service data |
| `/mnt/external-data/backups` | `root:external-data`, `2770` | `admin` and service group only |

Default POSIX ACLs preserve the intended access for normal files and
directories created below `shared` and `backups`. Services that explicitly
create mode `0600` files still require service-specific handling.

## Consequences

- ext4 provides native journaling, ownership, ACLs, and service-compatible
  read/write behavior on PiServ.
- The volume is not intended for direct macOS mounting; use a network protocol
  such as SMB or SFTP if Mac access is later required.
- `nofail` prevents a missing disk from blocking boot, but a service must use
  `RequiresMountsFor=/mnt/external-data` or an equivalent mount dependency to
  avoid writing into an unmounted fallback directory.
- Runtime discovery refuses zero or multiple `external-data` label matches,
  a model or serial mismatch, non-USB parent disks, unexpected filesystem
  layouts, and mount conflicts. It never formats or silently adopts a blank
  disk.
- `smartmontools` is installed by the base role. The base role validates the
  root NVMe health; the external-storage playbook validates the discovered
  external disk and uses a bridge-specific pass-through mode only when the
  discovered USB vendor requires it. External SMART is advisory by default and
  can be made a convergence requirement after the bridge path is accepted.
- Reformatting permanently removed the original APFS contents. Independent
  backups remain required.

## Validation

The live preparation completed with `ok=29 changed=7 failed=0`. Validation
confirmed:

- one GPT partition spanning 3.64 TiB;
- ext4 label `external-data` and a filesystem UUID;
- `has_journal` in the ext4 feature set;
- active mount with `nodev,nosuid`;
- `admin` membership in `external-data`;
- an ordinary user can read `shared` but cannot write it;
- an ordinary user cannot read `backups`;
- temporary read/write validation files were removed after testing.

The steady-state source of truth is
`ansible/playbooks/external-storage.yml`. The completed one-off destructive
migration playbook was removed so normal automation cannot reformat the live
volume.
