#!/usr/bin/env bash
set -euo pipefail

SSH_TARGET=admin@PiServ.local
MOUNT_ROOT=/mnt/pcloud
TARGET_SUBPATH="My Music/Podcasts/raiplaypodcast"
SERVICE_NAME=pcloudcc.service
KEEP_FILE=0
CHECK_SERVICE=1
SSH_OPTIONS=(-o BatchMode=yes -o ConnectTimeout=10)

usage() {
  cat <<'EOF'
Usage: scripts/check-pcloudcc-health.sh [options]

Upload and run the PiServ pcloudcc health check over SSH.

Options:
  --host TARGET          SSH target. Default: admin@PiServ.local
  --mount-root PATH      pCloud mount root. Default: /mnt/pcloud
  --target-subpath PATH  Path below mount root to write-test
  --service-name NAME    User systemd service name. Default: pcloudcc.service
  --skip-service         Do not check the user systemd service state
  --keep-file            Keep the remote round-trip test file
  -h, --help             Show this help
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

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REMOTE_SCRIPT="${SCRIPT_DIR}/remote/check-pcloudcc-health-remote.sh"
[[ -r "${REMOTE_SCRIPT}" ]] || fail "missing remote script: ${REMOTE_SCRIPT}"

remote_args=(
  --mount-root "${MOUNT_ROOT}"
  --target-subpath "${TARGET_SUBPATH}"
  --service-name "${SERVICE_NAME}"
)

if [[ "${CHECK_SERVICE}" -ne 1 ]]; then
  remote_args+=(--skip-service)
fi

if [[ "${KEEP_FILE}" -eq 1 ]]; then
  remote_args+=(--keep-file)
fi

ssh "${SSH_OPTIONS[@]}" "${SSH_TARGET}" bash -s -- "${remote_args[@]}" < "${REMOTE_SCRIPT}"
exit 0
