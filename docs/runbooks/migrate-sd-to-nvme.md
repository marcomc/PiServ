# Migrate microSD to NVMe

## Purpose

Move a microSD-booted PiServ system to the internal NVMe SSD and configure the
Raspberry Pi bootloader to try NVMe before falling back to microSD.

## Preconditions

- SSH works as `operator@piserv.example.com`.
- `operator` can run non-interactive sudo.
- The system is currently booted from microSD.
- The target NVMe disk is `/dev/nvme0n1`.
- Any existing content on `/dev/nvme0n1` can be destroyed.

## Operator Command

Preferred wrapper:

```sh
scripts/migrate-sd-to-nvme.sh --yes --reboot
```

Ansible equivalent:

```sh
ansible-playbook -i ansible/inventory.ini ansible/playbooks/migrate-sd-to-nvme.yml \
  -e allow_destructive_nvme_reimage=true
```

## Manual Command Sequence

The migration script performs this sequence on PiServ:

1. Confirm `/` and `/boot/firmware` are mounted from `/dev/mmcblk0`.
2. Confirm `/dev/nvme0n1` exists and is not mounted.
3. Repartition `/dev/nvme0n1` with:
   - `/dev/nvme0n1p1`: 512 MiB FAT32 boot partition.
   - `/dev/nvme0n1p2`: ext4 root partition using the remaining SSD space.
4. Copy `/` with `rsync -aAXH --numeric-ids --one-file-system`.
5. Copy `/boot/firmware` with `rsync -aAXH --numeric-ids --delete`.
6. Update target `/etc/fstab` to the NVMe partition identifiers.
7. Update target `cmdline.txt` to `root=PARTUUID=<nvme-root-partuuid>`.
8. Apply EEPROM `BOOT_ORDER=0xf16`.
9. Reboot and verify the active root and boot partitions.

## Live Result

Completed on 2026-07-02.

| Check | Result |
| --- | --- |
| Hostname | `PiServ` |
| Root before migration | `/dev/mmcblk0p2` |
| Boot before migration | `/dev/mmcblk0p1` |
| Root after migration | `/dev/nvme0n1p2` |
| Boot after migration | `/dev/nvme0n1p1` |
| NVMe root size | `117G` filesystem, `104G` available |
| NVMe root PARTUUID | `9a0f4355-02` |
| NVMe boot PARTUUID | `9a0f4355-01` |
| EEPROM boot order | `0xf16` |
| Bootloader version | `Tue May 26 15:01:25 UTC 2026` |
| Failed systemd units | `0` |

The microSD remains installed as fallback media. Its boot partition was
unmounted after post-boot verification.

## Verification Commands

```sh
ssh operator@piserv.example.com 'findmnt -n -o SOURCE /; findmnt -n -o SOURCE /boot/firmware'
ssh operator@piserv.example.com 'df -h / /boot/firmware'
ssh operator@piserv.example.com 'sudo rpi-eeprom-config | grep ^BOOT_ORDER='
ssh operator@piserv.example.com 'systemctl --failed --no-pager'
```

Expected current values:

```text
/dev/nvme0n1p2
/dev/nvme0n1p1
BOOT_ORDER=0xf16
```

## References

- [Raspberry Pi M.2 HAT+ NVMe boot documentation](https://www.raspberrypi.com/documentation/accessories/m2-hat-plus.html#boot-from-nvme)
- [Raspberry Pi boot order documentation](https://www.raspberrypi.com/documentation/computers/configuration.html#change-the-boot-order)
