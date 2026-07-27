# External SSD Storage Runbook

## Table of Contents

- [Purpose](#purpose)
- [Current State](#current-state)
- [Provisioning History](#provisioning-history)
- [Verification](#verification)
- [Service Access](#service-access)
- [Recovery](#recovery)

## Purpose

Operate the PiServ-owned external SSD as a journaled ext4 data volume with
shared service access and restricted backup storage.

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
disk identity, and keep the generated local file out of version control. The
playbook falls back to the committed example only for a clean-checkout syntax
check; its placeholders fail the disk identity assertion and are not a usable
live configuration.

## Provisioning History

The original APFS disk was destructively converted to this ext4 layout during
the 2026-07-23 provisioning. That one-off migration is complete; no destructive
playbook is retained. The steady-state playbook refuses an unexpected
filesystem instead of reformatting a mounted or existing volume.

Use the non-destructive convergence command for normal operation:

```sh
ansible-playbook ansible/playbooks/external-storage.yml
```

## Verification

Run these checks after reconnecting the disk or rebooting:

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
`ansible/group_vars/piserv.yml`. Every listed account must already exist; the
playbook rejects unknown users rather than creating them. Then converge:

```yaml
piserv_external_storage_service_users:
  - SERVICE_USER
piserv_external_storage_service_units:
  - SERVICE.service
piserv_external_storage_revoked_service_units: []
```

Removing a service user from this list removes its membership from
`external-data` on the next convergence without changing its other groups. The
listed active writing service units restart when membership changes so they
receive or lose storage access immediately; stopped units remain stopped. Human
administrators must start a new login session after their group membership
changes.

To remove a user and unit in the same convergence, put the departing unit in
`piserv_external_storage_revoked_service_units` for that run. This restarts the
still-running service immediately after its group access is revoked, before
the remaining storage validation; remove the unit from the temporary list after
the successful convergence.

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
