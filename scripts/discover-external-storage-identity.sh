#!/usr/bin/env bash
set -euo pipefail

DEVICE=""
WRITE_PATH=""

usage() {
  cat <<'EOF'
Usage: scripts/discover-external-storage-identity.sh [options]

Read the udev model and serial of one external USB disk and print the PiServ
external-storage identity YAML. This command is read-only unless --write is
provided.

Options:
  --device PATH  USB disk to inspect, for example /dev/sda
  --write PATH   Create the ignored identity file on this host; refuse if it exists
  -h, --help     Show this help
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

yaml_quote() {
  local value=$1
  value=${value//\'/\'\'}
  printf "'%s'" "${value}"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --device)
      [[ "$#" -ge 2 ]] || fail "--device requires a value"
      DEVICE=$2
      shift 2
      ;;
    --write)
      [[ "$#" -ge 2 ]] || fail "--write requires a value"
      WRITE_PATH=$2
      shift 2
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

for command_name in lsblk udevadm; do
  require_command "${command_name}"
done

if [[ -z "${DEVICE}" ]]; then
  usb_disk_listing=$(lsblk --nodeps --noheadings --paths --output NAME,TYPE,TRAN)
  usb_disks=()
  while IFS=' ' read -r disk_path disk_type disk_transport; do
    if [[ "${disk_type}" == "disk" && "${disk_transport}" == "usb" ]]; then
      usb_disks+=("${disk_path}")
    fi
  done <<< "${usb_disk_listing}"

  if [[ "${#usb_disks[@]}" -ne 1 ]]; then
    if [[ "${#usb_disks[@]}" -eq 0 ]]; then
      fail "no USB disk was discovered; attach the enclosure or pass --device"
    fi
    printf 'Discovered multiple USB disks:\n' >&2
    printf '  %s\n' "${usb_disks[@]}" >&2
    fail "pass --device with the disk selected by the operator"
  fi

  DEVICE=${usb_disks[0]}
fi

[[ -b "${DEVICE}" ]] || fail "not a block device: ${DEVICE}"

device_layout=$(lsblk --nodeps --noheadings --output TYPE,TRAN "${DEVICE}")
[[ "${device_layout}" == "disk usb" ]] ||
  fail "expected a USB disk, found: ${device_layout:-unknown}"

udev_properties=$(udevadm info --query=property --name="${DEVICE}")
model=$(awk -F= '$1 == "ID_MODEL" { print substr($0, index($0, "=") + 1); exit }' \
  <<< "${udev_properties}")
serial=$(awk -F= '$1 == "ID_SERIAL_SHORT" { print substr($0, index($0, "=") + 1); exit }' \
  <<< "${udev_properties}")

[[ -n "${model}" ]] || fail "udev did not report ID_MODEL for ${DEVICE}"
[[ -n "${serial}" ]] || fail "udev did not report ID_SERIAL_SHORT for ${DEVICE}"

quoted_model=$(yaml_quote "${model}")
quoted_serial=$(yaml_quote "${serial}")
identity_yaml=$(printf '%s\n' \
  '# Managed locally; this file is intentionally ignored by Git.' \
  "piserv_external_storage_expected_model: ${quoted_model}" \
  "piserv_external_storage_expected_serial: ${quoted_serial}")

printf 'device=%s\n' "${DEVICE}"
printf '%s\n' "${identity_yaml}"

if [[ -z "${WRITE_PATH}" ]]; then
  printf '%s\n' \
    'No file was written. Review the values, then rerun with:' \
    "  scripts/discover-external-storage-identity.sh --device ${DEVICE} --write ansible/vars/external-storage.yml"
  exit 0
fi

[[ ! -e "${WRITE_PATH}" ]] || fail "refusing to overwrite existing file: ${WRITE_PATH}"

write_parent=$(dirname -- "${WRITE_PATH}")
[[ -d "${write_parent}" ]] || fail "parent directory does not exist: ${write_parent}"

umask 077
install -m 0600 /dev/null "${WRITE_PATH}"
printf '%s\n' "${identity_yaml}" > "${WRITE_PATH}"
printf 'identity_file=%s\n' "${WRITE_PATH}"
exit 0
