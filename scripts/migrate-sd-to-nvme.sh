#!/usr/bin/env bash
set -euo pipefail

SSH_TARGET=operator@piserv.example.com
TARGET_DISK=/dev/nvme0n1
BOOT_ORDER=0xf16
CONFIRM=0
REBOOT=0
SSH_OPTIONS=(-o BatchMode=yes -o ConnectTimeout=10)

usage() {
  cat <<'EOF'
Usage: scripts/migrate-sd-to-nvme.sh --yes [options]

Destructively clone the currently booted microSD system to the Raspberry Pi
NVMe drive, then schedule EEPROM boot order for NVMe first and SD fallback.

Options:
  --host TARGET        SSH target. Default: operator@piserv.example.com
  --target-disk DISK  Disk to repartition and format. Default: /dev/nvme0n1
  --boot-order ORDER  EEPROM BOOT_ORDER value. Default: 0xf16
  --reboot            Reboot after preparing the NVMe and verify the result
  --yes               Required destructive-operation confirmation
  -h, --help          Show this help
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --host)
      [[ "$#" -ge 2 ]] || fail "--host requires a value"
      SSH_TARGET=$2
      shift 2
      ;;
    --target-disk)
      [[ "$#" -ge 2 ]] || fail "--target-disk requires a value"
      TARGET_DISK=$2
      shift 2
      ;;
    --boot-order)
      [[ "$#" -ge 2 ]] || fail "--boot-order requires a value"
      BOOT_ORDER=$2
      shift 2
      ;;
    --reboot)
      REBOOT=1
      shift
      ;;
    --yes)
      CONFIRM=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ "${CONFIRM}" -eq 1 ]] || fail "refusing to repartition ${TARGET_DISK} without --yes"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REMOTE_SCRIPT="${SCRIPT_DIR}/remote/migrate-sd-to-nvme-remote.sh"
[[ -r "${REMOTE_SCRIPT}" ]] || fail "missing remote script: ${REMOTE_SCRIPT}"

printf 'Target host: %s\n' "${SSH_TARGET}"
printf 'Target disk: %s\n' "${TARGET_DISK}"
printf 'Boot order: %s\n' "${BOOT_ORDER}"

ssh "${SSH_OPTIONS[@]}" "${SSH_TARGET}" \
  sudo install -m 0755 /dev/stdin /tmp/piserv-migrate-sd-to-nvme-remote.sh \
  < "${REMOTE_SCRIPT}"

ssh "${SSH_OPTIONS[@]}" "${SSH_TARGET}" sudo bash -s -- "${TARGET_DISK}" "${BOOT_ORDER}" <<'REMOTE_RUN'
set -euo pipefail
target_disk=$1
boot_order=$2
/tmp/piserv-migrate-sd-to-nvme-remote.sh "${target_disk}" "${boot_order}"
REMOTE_RUN

if [[ "${REBOOT}" -ne 1 ]]; then
  printf 'Prepared. Reboot %s to apply EEPROM changes and boot from NVMe.\n' "${SSH_TARGET}"
  exit 0
fi

ssh "${SSH_OPTIONS[@]}" "${SSH_TARGET}" sudo reboot || true

for attempt in $(seq 1 60); do
  sleep 5
  if ssh "${SSH_OPTIONS[@]}" "${SSH_TARGET}" sudo bash -s -- "${BOOT_ORDER}" <<'REMOTE_VERIFY'
set -euo pipefail
expected_boot_order=$1
findmnt -n -o SOURCE /
findmnt -n -o SOURCE /boot/firmware
rpi-eeprom-config | grep "^BOOT_ORDER=${expected_boot_order}$"
REMOTE_VERIFY
  then
    exit 0
  fi
  printf 'waiting for %s after reboot (%s/60)\n' "${SSH_TARGET}" "${attempt}"
done

fail "host did not pass post-reboot verification"
