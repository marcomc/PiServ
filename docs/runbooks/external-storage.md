# External SSD Storage Runbook

## Table of Contents

- [Purpose](#purpose)
- [Current State](#current-state)
- [Configure Device Identity](#configure-device-identity)
- [Provisioning History](#provisioning-history)
- [Verification](#verification)
- [Previous-Boot Diagnostics](#previous-boot-diagnostics)
- [Service Access](#service-access)
- [Recovery](#recovery)

## Purpose

Operate the PiServ-owned external SSD as a journaled ext4 data volume with
shared service access and restricted backup storage.

## Current State

| Item | Value |
| --- | --- |
| Device identity | Runtime label discovery verified against ignored local udev model and serial values |
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
The external-storage playbook discovers the unique partition labeled
`external-data`, resolves its parent disk, and compares its udev model and
serial to the ignored local identity values in
`ansible/vars/external-storage.yml`. Copy
`ansible/vars/external-storage.yml.example` to that ignored file and replace
both placeholders before applying. The playbook refuses zero or multiple label
matches, an identity mismatch, non-USB parents, unexpected filesystem layouts,
and mount conflicts. It never formats or automatically adopts a blank disk.

## Configure Device Identity

Before the first PiServ convergence, run the discovery helper on a Linux host
with the intended SSD and its USB enclosure attached. It does not need to be
PiServ, so the required identity can be obtained before the Pi is deployed.

```sh
scripts/discover-external-storage-identity.sh
```

The helper discovers exactly one USB disk, reads its Linux udev `ID_MODEL` and
`ID_SERIAL_SHORT` values, and prints only the corresponding YAML to stdout.
Operator guidance and the selected device are written to stderr, so the
read-only output can be redirected directly to a file. It writes nothing
unless explicitly requested. When this Linux host is also the Ansible
controller, review the printed disk and values, then create the ignored local
file there:

```sh
scripts/discover-external-storage-identity.sh \
  --write ansible/vars/external-storage.yml
```

`--write` always creates the file on the host running the helper. If the helper
runs on a separate Linux machine while the Ansible controller is macOS, use the
default read-only command and copy the printed YAML into the controller's
ignored `ansible/vars/external-storage.yml` file. PiServ's read-only preflight
will reject a value that does not match the later Linux udev identity before it
changes the host.

If multiple USB disks are attached, select the intended disk from a read-only
inventory and pass it explicitly:

```sh
lsblk -d -o NAME,TRAN,MODEL,SERIAL,SIZE,TYPE
scripts/discover-external-storage-identity.sh \
  --device /dev/sdX \
  --write ansible/vars/external-storage.yml
```

The helper refuses to overwrite an existing identity file. Inspect and update
an existing file manually if the physical enclosure is intentionally replaced.
Do not derive these values from macOS `diskutil`; Linux udev formatting is the
value that the preflight compares.

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

Before changing ACLs or services, the convergence playbook refuses a configured
filesystem UUID that `findmnt` reports at any target other than
`/mnt/external-data`.

Expected results are one ext4 partition labeled `external-data`, an active
`/mnt/external-data` mount with `nodev,nosuid`, and the ACLs recorded in
[Decision 0017](../decisions/0017-external-ssd-storage.md).

The base playbook installs `smartmontools` and validates the dynamically
discovered root NVMe health. The standalone external-storage playbook installs
the same package after its read-only identity preflight, then validates the
external disk before changing its mount, ACLs, groups, or services. On the live
ASM246X bridge, generic SMART autodetection did not work, but the dynamically
selected ASMedia NVMe pass-through mode returned `PASSED`. This is a
health-status check, not the deferred full SMART baseline capture. SMART
pass-through is optional by default; set
`piserv_external_storage_smart_required: true` after accepting a bridge
configuration if external SMART must block convergence.

The live 2026-07-23 validation proved that an ordinary user can read shared
data but cannot write it, while the restricted backup directory is not
readable by ordinary users.

### Bounded Backup-Write Test

The live 2026-07-29 test used a uniquely named 4 GiB file under
`/mnt/external-data/backups`. No backup-like service was running, the mount was
`/dev/sda1` with approximately 3.65 TB free, and the test was bounded by a
15-minute command timeout.

```sh
TEST_FILE="/mnt/external-data/backups/piserv-storage-test-$(date +%s)-$$.bin"
trap 'rm -f -- "$TEST_FILE" "$TEST_FILE.sha256"' EXIT
dd if=/dev/zero of="$TEST_FILE" bs=16M count=256 conv=fsync status=progress
sha256sum "$TEST_FILE" > "$TEST_FILE.sha256"
sha256sum -c "$TEST_FILE.sha256"
dd if="$TEST_FILE" of=/dev/null bs=16M iflag=direct status=progress
```

Observed results:

- write and flush completed: 4 GiB in 12.0 seconds at approximately 357 MB/s;
- checksum verification passed;
- direct readback completed: 4 GiB in 16.3 seconds at approximately 264 MB/s;
- cleanup passed and no test artifacts remained;
- no new USB reset, I/O, buffer-I/O, or ext4 kernel messages appeared after the
  test start marker.

### SMART Baseline

A read-only full SMART capture was completed on 2026-07-29 at 01:47 CEST after
the write test. The parent devices were discovered at runtime; the serial
numbers are intentionally not repeated in tracked documentation.

```sh
ROOT_SOURCE=$(findmnt --mountpoint / --output SOURCE --noheadings | xargs)
ROOT_DISK=/dev/$(lsblk --noheadings --output PKNAME "$ROOT_SOURCE" | xargs)
EXT_PART=$(sudo /usr/sbin/blkid --match-token LABEL=external-data --output device)
EXT_DISK=/dev/$(lsblk --noheadings --output PKNAME "$EXT_PART" | xargs)
sudo smartctl -x "$ROOT_DISK"
sudo smartctl -x -d sntasmedia "$EXT_DISK"
```

| Device | Model | Firmware | Health | Temperature | Used | Power-on | Unsafe shutdowns | Media/data errors | Error log |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| Root NVMe | `SSD 128GB` | `W0830D` | `PASSED` | 37 C | 0% | 580 h | 20 | 0 | 0 |
| External NVMe via ASMedia bridge | `CT4000P3SSD8` | `P9CR30A` | `PASSED` | 52 C; sensor 2: 62 C | 2% | 12,097 h | 165 | 0 | 0 |

The root query returned exit code 4 because the device rejected the optional
NVMe self-test-log request with `Invalid Field in Command`; its health status,
critical warning, media/data integrity, and error-log fields were clean. The
external query returned exit code 0. No SMART self-test was started, and the
`smartd` daemon remains disabled.

## Previous-Boot Diagnostics

PiServ retains compressed systemd journals on the root NVMe filesystem. This
keeps power, USB, and filesystem evidence available even when the external SSD
is disconnected or fails to remount. Inspect the previous boot after a restart
or unexpected power event with:

```sh
ssh admin@PiServ.local 'sudo journalctl --list-boots'
ssh admin@PiServ.local \
  'sudo journalctl -b -1 -k --no-pager | grep -Ei "under.?volt|throttl|usb|uas|reset|I/O error|Buffer I/O|EXT4-fs|sda|sda1"'
```

The journal is bounded to 1 GiB with a 5 GiB root-filesystem reserve, 128 MiB
per file, and 14-day retention. Persistent journald improves diagnosis but
cannot guarantee the final seconds of an abrupt power loss; compare the
previous-boot log with the current mount, USB link, and filesystem state.

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
`dmesg -T`, and `smartctl -x` output, then investigate the USB cable, enclosure
power, and filesystem before repair.

The original APFS contents were intentionally erased during preparation and
cannot be recovered from PiServ unless an independent copy exists.
