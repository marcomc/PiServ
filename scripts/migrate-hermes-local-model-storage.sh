#!/usr/bin/env bash

set -euo pipefail

piserv_host=${PISERV_HOST:-PiServ.local}
piserv_user=${PISERV_USER:-admin}
target="${piserv_user}@${piserv_host}"

ssh -o BatchMode=yes "${target}" 'sudo /bin/bash -s' <<'REMOTE'
set -euo pipefail

source_dir=/var/lib/hermes-agent/models
target_dir=/var/lib/hermes-models
services=(
  hermes-local-model-gemma-4-e2b.service
  hermes-local-model-granite-3-3-2b.service
)

for service in "${services[@]}"; do
  if systemctl is-active --quiet "${service}"; then
    printf 'Refusing to move active local-model storage: %s is active.\n' \
      "${service}" >&2
    exit 65
  fi
done

if [[ ! -d "${source_dir}" ]]; then
  printf 'Source model directory does not exist: %s\n' "${source_dir}" >&2
  exit 66
fi

if [[ -e "${target_dir}" ]]; then
  printf 'Target model directory already exists: %s\n' "${target_dir}" >&2
  exit 67
fi

source_mount="$(findmnt --noheadings --output SOURCE --target "${source_dir}")"
target_mount="$(findmnt --noheadings --output SOURCE --target "${target_dir%/*}")"
if [[ "${source_mount}" != "${target_mount}" ]]; then
  printf 'Refusing a cross-filesystem move: %s -> %s\n' \
    "${source_mount}" "${target_mount}" >&2
  exit 68
fi

mv -- "${source_dir}" "${target_dir}"
printf 'Moved local model storage: %s -> %s\n' "${source_dir}" "${target_dir}"
REMOTE
