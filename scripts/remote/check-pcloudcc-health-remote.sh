#!/usr/bin/env bash
set -euo pipefail

MOUNT_ROOT=/mnt/pcloud
TARGET_SUBPATH="My Music/Podcasts/raiplaypodcast"
SERVICE_NAME=pcloudcc.service
CHECK_SERVICE=1
KEEP_FILE=0

usage() {
  cat <<'EOF'
Usage: check-pcloudcc-health-remote.sh [options]

Validate a pcloudcc user-service mount and a writable target directory.

Options:
  --mount-root PATH       pCloud mount root. Default: /mnt/pcloud
  --target-subpath PATH   Path below mount root to write-test
  --service-name NAME     User systemd service name. Default: pcloudcc.service
  --skip-service          Do not check the user systemd service state
  --keep-file             Keep the round-trip test file
  -h, --help              Show this help
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --mount-root)
      [[ "$#" -ge 2 ]] || fail "--mount-root requires a value"
      MOUNT_ROOT=$2
      shift 2
      ;;
    --target-subpath)
      [[ "$#" -ge 2 ]] || fail "--target-subpath requires a value"
      TARGET_SUBPATH=$2
      shift 2
      ;;
    --service-name)
      [[ "$#" -ge 2 ]] || fail "--service-name requires a value"
      SERVICE_NAME=$2
      shift 2
      ;;
    --skip-service)
      CHECK_SERVICE=0
      shift
      ;;
    --keep-file)
      KEEP_FILE=1
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

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

for command_name in date findmnt grep hostname id rm systemctl; do
  require_command "${command_name}"
done

if [[ "${CHECK_SERVICE}" -eq 1 ]]; then
  RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  export XDG_RUNTIME_DIR="${RUNTIME_DIR}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${RUNTIME_DIR}/bus}"
  systemctl --user is-active --quiet "${SERVICE_NAME}" ||
    fail "user service is not active: ${SERVICE_NAME}"
fi

findmnt --mountpoint "${MOUNT_ROOT}" >/dev/null ||
  fail "pCloud mount is not active: ${MOUNT_ROOT}"

TARGET_DIR="${MOUNT_ROOT%/}/${TARGET_SUBPATH#/}"
[[ -d "${TARGET_DIR}" ]] || fail "target directory is missing: ${TARGET_DIR}"
[[ -w "${TARGET_DIR}" ]] || fail "target directory is not writable: ${TARGET_DIR}"

HOSTNAME=$(hostname)
STAMP=$(date +%Y%m%d-%H%M%S)
TEST_FILE="${TARGET_DIR}/.piserv-pcloud-health-${HOSTNAME}-${STAMP}-$$.txt"
PAYLOAD="piserv-pcloud-health ${HOSTNAME} ${STAMP} $$"

cleanup() {
  if [[ "${KEEP_FILE}" -ne 1 ]]; then
    rm -f -- "${TEST_FILE}"
  fi
}
trap cleanup EXIT

printf '%s\n' "${PAYLOAD}" > "${TEST_FILE}"
grep -Fx -- "${PAYLOAD}" "${TEST_FILE}" >/dev/null ||
  fail "round-trip content mismatch: ${TEST_FILE}"

if [[ "${KEEP_FILE}" -ne 1 ]]; then
  cleanup
  trap - EXIT
fi

printf 'pcloudcc_health=ok\n'
printf 'mount_root=%s\n' "${MOUNT_ROOT}"
printf 'target_dir=%s\n' "${TARGET_DIR}"
printf 'round_trip_file=%s\n' "${TEST_FILE}"
exit 0
