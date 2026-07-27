# External SSD Storage Runbook

## Table of Contents

- [Purpose](#purpose)
- [Current State](#current-state)
- [Preparation](#preparation)
- [Verification](#verification)
- [Service Access](#service-access)
- [Recovery](#recovery)

## Purpose

Prepare and operate the PiServ-owned external SSD as a journaled ext4 data
volume with shared service access and restricted backup storage.

## Current State

| Item | Value |
| --- | --- |
| Device identity | Locally configured model, serial, and stable by-id path |
| Partition layout | One GPT partition spanning 3.64 TiB |
| Filesystem | Journaled ext4 |
| Label | `external-data` |
| Mount source | Filesystem UUID, resolved by the convergence playbook |
| Mountpoint | `/mnt/external-data` |
| Shared data | `/mnt/external-data/shared` |
| Restricted backups | `/mnt/external-data/backups` |
| Service write group | `external-data` |
| Human administrator group | `admin` via named ACL |

The disk is attached through a USB 3 port and currently negotiates at 5 Gbps.

The disk identity is deliberately local rather than committed. Copy
`ansible/vars/external-storage.yml.example` to
`ansible/vars/external-storage.yml`, replace the placeholders with the verified
disk identity, and keep the generated local file out of version control.

## Preparation

The preparation playbook is destructive. It verifies the enclosure model,
serial, and that neither the disk nor any child block device is mounted,
installs its partitioning and ext4 tooling, then replaces the existing
partition table and filesystem signatures with one GPT partition, formats it as
ext4, and applies the steady-state policy. This reset is intentionally
non-idempotent and permanently destroys all data on the verified disk.

Run only after confirming that the disk contents may be erased:

```sh
ansible-playbook ansible/playbooks/prepare-external-storage.yml \
  -e piserv_external_storage_format_confirmed=true
```

The normal, non-destructive convergence command is:

```sh
ansible-playbook ansible/playbooks/external-storage.yml
```

## Verification

Run these checks after preparation, reconnect, or reboot:

```sh
ssh admin@PiServ.local \
  'findmnt --mountpoint /mnt/external-data; lsblk -e7 -f "$(findmnt --noheadings --output SOURCE --mountpoint /mnt/external-data)"'
ssh admin@PiServ.local \
  'getfacl -p /mnt/external-data/shared /mnt/external-data/backups'
```

Expected results are one ext4 partition labeled `external-data`, an active
`/mnt/external-data` mount with `nodev,nosuid`, and the ACLs recorded in
[Decision 0017](../decisions/0017-external-ssd-storage.md).

The live 2026-07-23 validation proved that an ordinary user can read shared
data but cannot write it, while the restricted backup directory is not
readable by ordinary users.

## Service Access

Add only services that need write access to the dedicated service group through
`piserv_external_storage_service_users` in
`ansible/group_vars/piserv.yml`, then converge:

```yaml
piserv_external_storage_service_users:
  - SERVICE_USER
piserv_external_storage_service_units:
  - SERVICE.service
```

Removing a service user from this list removes its membership from
`external-data` on the next convergence without changing its other groups. The
listed writing service units restart when membership changes so they receive or
lose storage access immediately. Human administrators must start a new login
session after their group membership changes.

Service units that use this path should include:

```ini
RequiresMountsFor=/mnt/external-data
```

Use `shared` for data that ordinary users may read. Use `backups` for backup
content that must remain limited to the `admin` group and approved services.

## Recovery

If the disk is disconnected, stop dependent services before removal. After
reconnection, confirm the USB link is at 5 Gbps and run:

```sh
ansible-playbook ansible/playbooks/external-storage.yml
```

If the mount is unhealthy, do not reformat it. Capture `lsblk`, `findmnt`,
`dmesg -T`, and `smartctl` output if the utility is installed, then investigate
the USB cable, enclosure power, and filesystem before repair.

The original APFS contents were intentionally erased during preparation and
cannot be recovered from PiServ unless an independent copy exists.
