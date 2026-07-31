#!/usr/bin/env bash

set -euo pipefail

piserv_host=${PISERV_HOST:-PiServ.local}
piserv_user=${PISERV_USER:-admin}
target="${piserv_user}@${piserv_host}"

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: %s MODEL_ID\n' "$0" >&2
  exit 64
fi

model_id=$1
case "${model_id}" in
  gemma-4-e2b|granite-3-3-2b) ;;
  *)
    printf 'Unsupported configured local model: %s\n' "${model_id}" >&2
    exit 64
    ;;
esac

unit_name="hermes-local-provider-proof-${model_id}-$(date -u +%Y%m%d%H%M%S)"

printf 'Starting isolated local-provider proof unit: %s\n' "${unit_name}"
ssh -o BatchMode=yes "${target}" \
  "sudo systemd-run --unit='${unit_name}' --wait --pipe --service-type=exec --property=RuntimeMaxSec=10min --property=OOMScoreAdjust=500 --setenv='MODEL_ID=${model_id}' /bin/bash -s" <<'REMOTE'
set -euo pipefail

source_home=/var/lib/hermes-agent
source_codex_home="${source_home}/codex"
model_id="${MODEL_ID:?MODEL_ID is required}"
service_name="hermes-local-model-${model_id}.service"
timestamp="$(date --utc +%Y%m%dT%H%M%SZ)"
marker="PISERV_LOCAL_PROVIDER_PROOF_${model_id}_${timestamp}"
work_dir="$(mktemp -d /run/hermes-local-provider-proof.XXXXXX)"
test_home="${work_dir}/home"
backup_dir="${work_dir}/backup"
stderr_file="${work_dir}/agent-stderr.txt"

run_as_test_hermes() {
  runuser -u hermes-agent -- env \
    HOME="${test_home}" \
    HERMES_HOME="${test_home}" \
    CODEX_HOME="${test_home}/codex" \
    "$@"
}

run_as_source_hermes() {
  runuser -u hermes-agent -- env \
    HOME="${source_home}" \
    HERMES_HOME="${source_home}" \
    CODEX_HOME="${source_codex_home}" \
    "$@"
}

wait_for_http() {
  local url=$1
  local attempts=$2
  local delay_seconds=$3
  local attempt

  for attempt in $(seq 1 "${attempts}"); do
    if curl --fail --silent "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${delay_seconds}"
  done

  printf 'Endpoint did not become healthy: %s\n' "${url}" >&2
  return 1
}

wait_for_model_http() {
  local url=$1
  local attempts=$2
  local delay_seconds=$3
  local attempt

  for attempt in $(seq 1 "${attempts}"); do
    if curl --fail --silent "${url}" >/dev/null 2>&1; then
      return 0
    fi
    if systemctl is-failed --quiet "${service_name}"; then
      printf 'Local model service failed before becoming healthy: %s\n' \
        "${service_name}" >&2
      journalctl --unit "${service_name}" --no-pager --lines=80 >&2
      return 1
    fi
    sleep "${delay_seconds}"
  done

  printf 'Local model service did not become healthy: %s\n' "${service_name}" >&2
  return 1
}

cleanup() {
  local status=$?

  systemctl stop "${service_name}" >/dev/null 2>&1 || true
  rm -rf -- "${work_dir}"
  exit "${status}"
}
trap cleanup EXIT

if ! systemctl cat "${service_name}" >/dev/null; then
  printf 'Configured local model service is unavailable: %s\n' "${service_name}" >&2
  exit 65
fi

if systemctl list-units --all --plain --no-legend 'hermes-local-model-*.service' \
  | awk '$3 == "active" { found = 1 } END { exit !found }'; then
  printf 'Refusing to interrupt an active managed local-model service.\n' >&2
  exit 66
fi

model_port="$(systemctl show "${service_name}" --property=ExecStart --value \
  | sed -n 's/.*--port \([0-9][0-9]*\).*/\1/p')"
if [[ ! "${model_port}" =~ ^[0-9]+$ ]]; then
  printf 'Unable to determine local model port: %s\n' "${model_id}" >&2
  exit 67
fi

available_run_bytes="$(df --output=avail -B1 /run | awk 'NR == 2 { print $1 }')"
if [[ ! "${available_run_bytes}" =~ ^[0-9]+$ ]] || (( available_run_bytes < 268435456 )); then
  printf 'At least 256 MiB free under /run is required for the isolated proof.\n' >&2
  exit 68
fi

install -d -o hermes-agent -g hermes-agent -m 0700 "${test_home}" "${backup_dir}"
chmod 0711 "${work_dir}"
run_as_source_hermes hermes backup --output "${backup_dir}" >/dev/null
source_archive="$(find "${backup_dir}" -maxdepth 1 -type f -name 'hermes-backup-*.zip' -print -quit)"
if [[ -z "${source_archive}" ]]; then
  printf 'Source backup command did not create an archive.\n' >&2
  exit 69
fi

run_as_test_hermes hermes import --force "${source_archive}" >/dev/null

memory_file="${test_home}/memories/MEMORY.md"
skill_dir="${test_home}/skills/piserv-local-provider-proof"
install -d -o hermes-agent -g hermes-agent -m 0700 "${memory_file%/*}" "${skill_dir}"
{
  printf '%s\n' '<!-- PiServ local provider proof: START -->'
  printf '%s\n' "${marker}"
  printf '%s\n' '<!-- PiServ local provider proof: END -->'
} >>"${memory_file}"
chown hermes-agent:hermes-agent "${memory_file}"
chmod 0600 "${memory_file}"
cat >"${skill_dir}/SKILL.md" <<'SKILL'
---
name: piserv-local-provider-proof
description: Read-only fixture for a Hermes local-provider capability test.
---

# PiServ Local Provider Proof

Use the memory tool to find the PiServ local-provider proof marker in built-in
memory. Return that exact marker and no other text. Do not perform actions or
change state.
SKILL
chown hermes-agent:hermes-agent "${skill_dir}/SKILL.md"
chmod 0600 "${skill_dir}/SKILL.md"

test_skills="$(run_as_test_hermes hermes skills list)"
[[ "${test_skills}" == *piserv-local-provider-proof* ]]

run_as_test_hermes hermes config set model.default "${model_id}" >/dev/null
run_as_test_hermes hermes config set model.provider custom:piserv-local-provider-proof >/dev/null
run_as_test_hermes hermes config set model.context_length 65536 >/dev/null
run_as_test_hermes hermes config set model.max_tokens 32 >/dev/null
run_as_test_hermes hermes config set \
  providers.piserv-local-provider-proof.base_url \
  "http://127.0.0.1:${model_port}/v1" >/dev/null
run_as_test_hermes hermes config set \
  providers.piserv-local-provider-proof.default_model "${model_id}" >/dev/null
run_as_test_hermes hermes config set \
  providers.piserv-local-provider-proof.api_mode chat_completions >/dev/null
run_as_test_hermes hermes config set \
  providers.piserv-local-provider-proof.max_output_tokens 32 >/dev/null

systemctl reset-failed "${service_name}" 2>/dev/null || true
systemctl start "${service_name}"
wait_for_model_http "http://127.0.0.1:${model_port}/health" 120 5

set +e
agent_output="$(run_as_test_hermes timeout --signal=TERM --kill-after=15s 7m \
  hermes --oneshot 'Use the loaded proof skill. Return only the marker it requests.' \
  --provider custom:piserv-local-provider-proof \
  --model "${model_id}" \
  --toolsets memory,skills \
  --skills piserv-local-provider-proof \
  2>"${stderr_file}")"
agent_status=$?
set -e

if (( agent_status != 0 )); then
  printf 'Hermes local-provider invocation failed with exit status %s.\n' \
    "${agent_status}" >&2
  if [[ -s "${stderr_file}" ]]; then
    sed -n '1,160p' "${stderr_file}" >&2
  fi
  exit "${agent_status}"
fi

if [[ "${agent_output}" != *"${marker}"* ]]; then
  printf 'Hermes did not return the local-provider proof marker.\n' >&2
  printf 'Response: %s\n' "${agent_output}" >&2
  exit 70
fi

printf 'model_id=%s\n' "${model_id}"
printf 'response_contains_marker=true\n'
printf 'service_state=%s\n' \
  "$(systemctl show "${service_name}" --property=ExecMainStatus --value)"
REMOTE
