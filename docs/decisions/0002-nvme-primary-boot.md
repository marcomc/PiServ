# 0002: NVMe Primary Boot

## Status

Accepted on 2026-07-02.

## Context

PiServ has a 128 GB NVMe SSD and was initially booted from a 64 GB microSD
card. The desired operating model is to run from NVMe for capacity and storage
performance while keeping the microSD installed as fallback boot media.

## Decision

Use NVMe as the primary boot and root device.

The active EEPROM setting is:

```text
BOOT_ORDER=0xf16
```

For this Raspberry Pi bootloader order, the effective sequence is:

1. NVMe.
2. microSD.
3. Restart boot scanning.

The NVMe layout is:

| Partition | Purpose | Size |
| --- | --- | --- |
| `/dev/nvme0n1p1` | FAT32 boot firmware | 512 MiB |
| `/dev/nvme0n1p2` | ext4 root filesystem | Remaining SSD space |

## Consequences

- Normal boots use the NVMe SSD.
- The microSD can remain installed for fallback if the NVMe image is missing or
  invalid.
- The root filesystem now has the full usable SSD capacity.
- Re-running migration automation intentionally destroys `/dev/nvme0n1`.

## Validation

Verified after reboot on 2026-07-02:

| Check | Result |
| --- | --- |
| `/` source | `/dev/nvme0n1p2` |
| `/boot/firmware` source | `/dev/nvme0n1p1` |
| Root filesystem size | `117G` |
| EEPROM boot order | `0xf16` |
| Bootloader status | Up to date |
| Failed systemd units | `0` |
