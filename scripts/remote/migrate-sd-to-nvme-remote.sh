#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_DISK=${1:-/dev/nvme0n1}
BOOT_ORDER=${2:-0xf16}

case "${TARGET_DISK}" in
  *[0-9])
    TARGET_BOOT="${TARGET_DISK}p1"
    TARGET_ROOT="${TARGET_DISK}p2"
    ;;
  *)
    TARGET_BOOT="${TARGET_DISK}1"
    TARGET_ROOT="${TARGET_DISK}2"
    ;;
esac

MOUNT_ROOT=/mnt/piserv-nvme-root
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="/root/piserv-nvme-migration-${STAMP}.log"

info() {
  printf '\n== %s ==\n' "$1"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  set +e
  if findmnt -rn "${MOUNT_ROOT}/boot/firmware" >/dev/null 2>&1; then
    umount "${MOUNT_ROOT}/boot/firmware"
  fi
  if findmnt -rn "${MOUNT_ROOT}" >/dev/null 2>&1; then
    umount "${MOUNT_ROOT}"
  fi
  rmdir "${MOUNT_ROOT}" 2>/dev/null
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

trap cleanup EXIT
# shellcheck disable=SC2312 # tee is intentional best-effort log fan-out.
exec > >(tee -a "${LOG}") 2>&1

USER_ID=$(id -u)
[[ "${USER_ID}" -eq 0 ]] || fail "run as root"

for command_name in awk blkid findmnt lsblk mkfs.ext4 mkfs.vfat parted partprobe \
  rpi-eeprom-config rsync sed sync udevadm umount wipefs; do
  require_command "${command_name}"
done

info "preflight"
[[ -b "${TARGET_DISK}" ]] || fail "target disk not found: ${TARGET_DISK}"

ROOT_SOURCE=$(findmnt -n -o SOURCE /)
BOOT_SOURCE=$(findmnt -n -o SOURCE /boot/firmware)
printf 'root source: %s\n' "${ROOT_SOURCE}"
printf 'boot source: %s\n' "${BOOT_SOURCE}"
printf 'target disk: %s\n' "${TARGET_DISK}"
printf 'boot order: %s\n' "${BOOT_ORDER}"

case "${ROOT_SOURCE}" in
  /dev/mmcblk*) ;;
  *) fail "root is not currently on microSD: ${ROOT_SOURCE}" ;;
esac

case "${BOOT_SOURCE}" in
  /dev/mmcblk*) ;;
  *) fail "boot firmware is not currently on microSD: ${BOOT_SOURCE}" ;;
esac

if findmnt -rn -S "${TARGET_DISK}" >/dev/null 2>&1 ||
  findmnt -rn -S "${TARGET_BOOT}" >/dev/null 2>&1 ||
  findmnt -rn -S "${TARGET_ROOT}" >/dev/null 2>&1; then
  fail "target disk or target partitions are mounted"
fi

if [[ -e "${MOUNT_ROOT}" ]]; then
  MOUNT_ROOT_ENTRY=$(find "${MOUNT_ROOT}" -mindepth 1 -maxdepth 1 -print -quit)
  if [[ -n "${MOUNT_ROOT_ENTRY}" ]]; then
    fail "mount directory is not empty: ${MOUNT_ROOT}"
  fi
fi

info "source layout"
lsblk -e7 -o NAME,PATH,TYPE,SIZE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL
cat /etc/fstab
cat /proc/cmdline

info "wipe old NVMe signatures"
wipefs --all --force "${TARGET_DISK}"

info "partition NVMe"
parted --script "${TARGET_DISK}" \
  mklabel msdos \
  mkpart primary fat32 1MiB 513MiB \
  set 1 boot on \
  set 1 lba on \
  mkpart primary ext4 513MiB 100%
partprobe "${TARGET_DISK}"
udevadm settle

for device_path in "${TARGET_BOOT}" "${TARGET_ROOT}"; do
  for _ in $(seq 1 20); do
    [[ -b "${device_path}" ]] && break
    sleep 1
  done
  [[ -b "${device_path}" ]] || fail "partition did not appear: ${device_path}"
done

info "format NVMe filesystems"
mkfs.vfat -F 32 -n bootfs "${TARGET_BOOT}"
mkfs.ext4 -F -L rootfs "${TARGET_ROOT}"

info "mount target"
mkdir -p "${MOUNT_ROOT}"
mount "${TARGET_ROOT}" "${MOUNT_ROOT}"
mkdir -p "${MOUNT_ROOT}/boot/firmware"
mount "${TARGET_BOOT}" "${MOUNT_ROOT}/boot/firmware"

info "copy root filesystem"
rsync -aAXH --numeric-ids --one-file-system --stats \
  --exclude='/boot/firmware/*' \
  --exclude='/dev/*' \
  --exclude='/proc/*' \
  --exclude='/sys/*' \
  --exclude='/tmp/*' \
  --exclude='/run/*' \
  --exclude='/mnt/*' \
  --exclude='/media/*' \
  --exclude='/lost+found' \
  / "${MOUNT_ROOT}/"

info "copy boot firmware"
rsync -aAXH --numeric-ids --delete --stats \
  /boot/firmware/ "${MOUNT_ROOT}/boot/firmware/"

info "prepare runtime mountpoints"
mkdir -p "${MOUNT_ROOT}/dev" "${MOUNT_ROOT}/proc" "${MOUNT_ROOT}/sys" \
  "${MOUNT_ROOT}/tmp" "${MOUNT_ROOT}/run" "${MOUNT_ROOT}/mnt" "${MOUNT_ROOT}/media"
chmod 1777 "${MOUNT_ROOT}/tmp"
chmod 755 "${MOUNT_ROOT}/dev" "${MOUNT_ROOT}/proc" "${MOUNT_ROOT}/sys" \
  "${MOUNT_ROOT}/run" "${MOUNT_ROOT}/mnt" "${MOUNT_ROOT}/media"

info "update target identifiers"
BOOT_PARTUUID=$(blkid -s PARTUUID -o value "${TARGET_BOOT}")
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${TARGET_ROOT}")
printf 'target boot PARTUUID: %s\n' "${BOOT_PARTUUID}"
printf 'target root PARTUUID: %s\n' "${ROOT_PARTUUID}"

cp "${MOUNT_ROOT}/etc/fstab" "${MOUNT_ROOT}/etc/fstab.pre-nvme-${STAMP}"
awk -v boot_partuuid="${BOOT_PARTUUID}" -v root_partuuid="${ROOT_PARTUUID}" '
  BEGIN {
    boot_seen = 0
    root_seen = 0
  }
  $2 == "/boot/firmware" {
    $1 = "PARTUUID=" boot_partuuid
    boot_seen = 1
  }
  $2 == "/" {
    $1 = "PARTUUID=" root_partuuid
    root_seen = 1
  }
  { print }
  END {
    if (!boot_seen) {
      print "PARTUUID=" boot_partuuid, "/boot/firmware", "vfat", "defaults", "0", "2"
    }
    if (!root_seen) {
      print "PARTUUID=" root_partuuid, "/", "ext4", "defaults,noatime", "0", "1"
    }
  }
' OFS='	' "${MOUNT_ROOT}/etc/fstab" > "${MOUNT_ROOT}/etc/fstab.nvme"
mv "${MOUNT_ROOT}/etc/fstab.nvme" "${MOUNT_ROOT}/etc/fstab"

cp "${MOUNT_ROOT}/boot/firmware/cmdline.txt" \
  "${MOUNT_ROOT}/boot/firmware/cmdline.txt.pre-nvme-${STAMP}"
sed -i -E "s#root=PARTUUID=[^[:space:]]+#root=PARTUUID=${ROOT_PARTUUID}#" \
  "${MOUNT_ROOT}/boot/firmware/cmdline.txt"
awk 'END { exit (NR == 1 ? 0 : 1) }' "${MOUNT_ROOT}/boot/firmware/cmdline.txt" ||
  fail "cmdline.txt must contain exactly one physical line"
CMDLINE_ROOT_COUNT=$(
  tr ' ' '\n' < "${MOUNT_ROOT}/boot/firmware/cmdline.txt" |
    grep -c "^root=PARTUUID=${ROOT_PARTUUID}$"
)
[[ "${CMDLINE_ROOT_COUNT}" -eq 1 ]] ||
  fail "cmdline.txt does not contain exactly one target root PARTUUID"

info "target config verification"
cat "${MOUNT_ROOT}/etc/fstab"
cat "${MOUNT_ROOT}/boot/firmware/cmdline.txt"
findmnt -R -o TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL "${MOUNT_ROOT}"

info "schedule bootloader config"
rpi-eeprom-config > "/root/piserv-eeprom-before-${STAMP}.conf"
cp "/root/piserv-eeprom-before-${STAMP}.conf" "/root/piserv-eeprom-nvme-${STAMP}.conf"
if grep -q '^BOOT_ORDER=' "/root/piserv-eeprom-nvme-${STAMP}.conf"; then
  sed -i "s/^BOOT_ORDER=.*/BOOT_ORDER=${BOOT_ORDER}/" \
    "/root/piserv-eeprom-nvme-${STAMP}.conf"
else
  printf 'BOOT_ORDER=%s\n' "${BOOT_ORDER}" >> "/root/piserv-eeprom-nvme-${STAMP}.conf"
fi
cat "/root/piserv-eeprom-nvme-${STAMP}.conf"
rpi-eeprom-config --apply "/root/piserv-eeprom-nvme-${STAMP}.conf"

info "sync target"
sync

info "migration prepared"
printf 'log: %s\n' "${LOG}"
printf 'next: reboot and verify root is %s\n' "${TARGET_ROOT}"
