#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/piserv-target.sh
source "${script_dir}/lib/piserv-target.sh"
target="$(piserv_ssh_target)"
unit_name="hermes-persistence-proof-$(date -u +%Y%m%d%H%M%S)"

printf 'Starting transient proof unit: %s\n' "${unit_name}"
set +e
ssh -o BatchMode=yes "${target}" \
  "sudo systemd-run --unit=${unit_name} --wait --pipe --service-type=exec --property=RuntimeMaxSec=20min /bin/bash -s" <<'REMOTE'
set -euo pipefail

source_home=/var/lib/hermes-agent
source_codex_home="${source_home}/codex"
dashboard_service=hermes-agent-dashboard.service
stage_dashboard_port=19119
local_model_port=18083
model_path=/var/lib/hermes-models/granite-3.3-2b-instruct-Q4_K_M.gguf
model_id=granite-3-3-2b
hermes_minimum_context=65536
temporary_server_context=8192
provider_output_tokens=32
provider_timeout_seconds=180
timestamp="$(date --utc +%Y%m%dT%H%M%SZ)"
marker="PISERV_PERSISTENCE_PROOF_${timestamp}"
work_dir="$(mktemp -d /run/hermes-persistence-proof.XXXXXX)"
stage_home="${work_dir}/stage"
restore_home="${work_dir}/restore"
source_backup_dir="${work_dir}/source-backup"
stage_backup_dir="${work_dir}/stage-backup"
provider_stderr_file="${work_dir}/provider-stderr.txt"
stage_dashboard_unit="hermes-persistence-stage-dashboard-${timestamp}"
local_model_unit="hermes-persistence-local-model-${timestamp}"

run_as_source_hermes() {
  sudo -u hermes-agent -H env \
    HOME="${source_home}" \
    HERMES_HOME="${source_home}" \
    CODEX_HOME="${source_codex_home}" \
    "$@"
}

run_as_stage_hermes() {
  sudo -u hermes-agent -H env \
    HOME="${stage_home}" \
    HERMES_HOME="${stage_home}" \
    CODEX_HOME="${stage_home}/codex" \
    "$@"
}

run_as_restored_hermes() {
  sudo -u hermes-agent -H env \
    HOME="${restore_home}" \
    HERMES_HOME="${restore_home}" \
    CODEX_HOME="${restore_home}/codex" \
    "$@"
}

wait_for_http() {
  local url=$1
  local attempts=$2
  local delay_seconds=$3
  local attempt

  for attempt in $(seq 1 "${attempts}"); do
    if curl --fail --silent --max-time 5 "${url}" >/dev/null; then
      return 0
    fi
    sleep "${delay_seconds}"
  done

  printf 'Endpoint did not become healthy: %s\n' "${url}" >&2
  return 1
}

cleanup() {
  local status=$?

  systemctl stop "${stage_dashboard_unit}.service" >/dev/null 2>&1 || true
  systemctl stop "${local_model_unit}.service" >/dev/null 2>&1 || true
  rm -rf -- "${work_dir}"
  exit "${status}"
}
trap cleanup EXIT

if ! systemctl is-active --quiet "${dashboard_service}"; then
  printf 'Source dashboard is not active: %s\n' "${dashboard_service}" >&2
  exit 65
fi

mapfile -t active_local_model_units < <(
  systemctl list-units --type=service --state=active --no-legend --plain \
    'hermes-local-model-*.service' | awk '{print $1}'
)
if (( ${#active_local_model_units[@]} > 0 )); then
  printf 'Refusing to run alongside active local-model services: %s\n' \
    "${active_local_model_units[*]}" >&2
  exit 66
fi

if ss --listening --tcp --numeric | grep --quiet ":${stage_dashboard_port} "; then
  printf 'Stage dashboard port is already in use: %s\n' "${stage_dashboard_port}" >&2
  exit 67
fi

if ss --listening --tcp --numeric | grep --quiet ":${local_model_port} "; then
  printf 'Temporary local-model port is already in use: %s\n' "${local_model_port}" >&2
  exit 68
fi

if [[ ! -f "${model_path}" ]]; then
  printf 'Pinned Granite model is unavailable: %s\n' "${model_path}" >&2
  exit 69
fi

if [[ "$(stat -fc %T /sys/fs/cgroup)" != cgroup2fs ]]; then
  printf 'The cgroup v2 filesystem is unavailable for the local-provider proof.\n' >&2
  exit 70
fi
controllers="$(< /sys/fs/cgroup/cgroup.controllers)"
if [[ " ${controllers} " != *' memory '* ]]; then
  printf 'The cgroup v2 memory controller is unavailable for the local-provider proof.\n' >&2
  exit 70
fi

available_run_bytes="$(df --output=avail -B1 /run | awk 'NR == 2 { print $1 }')"
if [[ ! "${available_run_bytes}" =~ ^[0-9]+$ ]] || (( available_run_bytes < 268435456 )); then
  printf 'At least 256 MiB free under /run is required for the isolated proof.\n' >&2
  exit 70
fi

# Exercise the production service restart without adding test content to it.
systemctl restart "${dashboard_service}"
wait_for_http http://127.0.0.1:9119/ 30 1

install -d -o hermes-agent -g hermes-agent -m 0711 "${work_dir}"
install -d -o hermes-agent -g hermes-agent -m 0700 \
  "${source_backup_dir}" "${stage_backup_dir}" "${stage_home}" "${restore_home}"

# Clone the current Hermes state first. All fixtures remain inside /run.
run_as_source_hermes hermes backup --output "${source_backup_dir}" >/dev/null
source_archive="$(find "${source_backup_dir}" -maxdepth 1 -type f -name 'hermes-backup-*.zip' -print -quit)"
if [[ -z "${source_archive}" ]]; then
  printf 'Source backup command did not create an archive.\n' >&2
  exit 71
fi

run_as_stage_hermes hermes import --force "${source_archive}" >/dev/null
rm -- "${source_archive}"

stage_memory_file="${stage_home}/memories/MEMORY.md"
stage_skill_dir="${stage_home}/skills/piserv-persistence-proof"
if [[ -e "${stage_skill_dir}" ]]; then
  printf 'Refusing to replace an existing staged fixture skill.\n' >&2
  exit 72
fi

install -d -o hermes-agent -g hermes-agent -m 0700 \
  "${stage_memory_file%/*}" "${stage_skill_dir}" "${stage_home}/workspace"
{
  printf '%s\n' '<!-- PiServ persistence proof: START -->'
  printf '%s\n' "${marker}"
  printf '%s\n' '<!-- PiServ persistence proof: END -->'
} >>"${stage_memory_file}"
chown hermes-agent:hermes-agent "${stage_memory_file}"
chmod 0600 "${stage_memory_file}"
cat >"${stage_skill_dir}/SKILL.md" <<'SKILL'
---
name: piserv-persistence-proof
description: Read-only, non-sensitive fixture used to verify Hermes state persistence.
---

# PiServ Persistence Proof

When asked about the PiServ persistence proof, return the exact marker stored
in built-in memory. Do not perform actions or change state.
SKILL
chown hermes-agent:hermes-agent "${stage_skill_dir}/SKILL.md"
chmod 0600 "${stage_skill_dir}/SKILL.md"

systemd-run --unit="${stage_dashboard_unit}" --service-type=exec \
  --uid=hermes-agent --gid=hermes-agent \
  --setenv="HOME=${stage_home}" \
  --setenv="HERMES_HOME=${stage_home}" \
  --setenv="CODEX_HOME=${stage_home}/codex" \
  --property="WorkingDirectory=${stage_home}/workspace" \
  --property=RuntimeMaxSec=5min \
  /usr/local/bin/hermes dashboard --isolated --host 127.0.0.1 \
  --port "${stage_dashboard_port}" --no-open --skip-build >/dev/null
wait_for_http "http://127.0.0.1:${stage_dashboard_port}/" 30 1

systemctl restart "${stage_dashboard_unit}.service"
wait_for_http "http://127.0.0.1:${stage_dashboard_port}/" 30 1
grep --fixed-strings --quiet "${marker}" "${stage_memory_file}"
stage_skills="$(run_as_stage_hermes hermes skills list)"
[[ "${stage_skills}" == *piserv-persistence-proof* ]]

run_as_stage_hermes hermes backup --output "${stage_backup_dir}" >/dev/null
stage_archive="$(find "${stage_backup_dir}" -maxdepth 1 -type f -name 'hermes-backup-*.zip' -print -quit)"
if [[ -z "${stage_archive}" ]]; then
  printf 'Staged backup command did not create an archive.\n' >&2
  exit 73
fi
stage_archive_sha256="$(sha256sum "${stage_archive}" | awk '{print $1}')"
stage_archive_bytes="$(stat --format=%s "${stage_archive}")"

run_as_restored_hermes hermes import --force "${stage_archive}" >/dev/null
grep --fixed-strings --quiet "${marker}" "${restore_home}/memories/MEMORY.md"
test -f "${restore_home}/skills/piserv-persistence-proof/SKILL.md"
restored_skills="$(run_as_restored_hermes hermes skills list)"
[[ "${restored_skills}" == *piserv-persistence-proof* ]]

# Configure only the restored clone for a bounded local-provider migration.
run_as_restored_hermes hermes config set model.default "${model_id}" >/dev/null
run_as_restored_hermes hermes config set model.provider \
  custom:piserv-persistence-proof >/dev/null
# Hermes requires its declared model window to meet the 64K local-model policy.
# The generated proof request remains well within the temporary server's 8K cap.
run_as_restored_hermes hermes config set model.context_length \
  "${hermes_minimum_context}" >/dev/null
run_as_restored_hermes hermes config set model.max_tokens \
  "${provider_output_tokens}" >/dev/null
run_as_restored_hermes hermes config set \
  providers.piserv-persistence-proof.base_url \
  "http://127.0.0.1:${local_model_port}/v1" >/dev/null
run_as_restored_hermes hermes config set \
  providers.piserv-persistence-proof.default_model "${model_id}" >/dev/null
run_as_restored_hermes hermes config set \
  providers.piserv-persistence-proof.api_mode chat_completions >/dev/null
run_as_restored_hermes hermes config set \
  providers.piserv-persistence-proof.max_output_tokens \
  "${provider_output_tokens}" >/dev/null

# Use an independent low-context runtime for migration validation. Its cgroup
# policy matches the managed local-model service and is checked below.
systemd-run --unit="${local_model_unit}" --service-type=exec \
  --uid=hermes-agent --gid=hermes-agent \
  --property=RuntimeMaxSec=10min \
  --property=CPUQuota=200% \
  --property=TasksMax=48 \
  --property=LimitAS=4G \
  --property=MemoryHigh=2500M \
  --property=MemoryMax=3200M \
  --property=MemorySwapMax=512M \
  --property=OOMScoreAdjust=500 \
  --property=TimeoutStopSec=15s \
  /usr/local/bin/llama-server --model "${model_path}" --alias "${model_id}" \
  --host 127.0.0.1 --port "${local_model_port}" \
  --ctx-size "${temporary_server_context}" --parallel 1 \
  --threads 2 --threads-batch 2 --cache-type-k q4_0 --cache-type-v q4_0 \
  --cache-ram 64 --n-predict "${provider_output_tokens}" --no-warmup \
  --jinja --no-mmproj --no-webui >/dev/null
local_model_limits="$(systemctl show "${local_model_unit}.service" \
  --property=MemoryHigh --property=MemoryMax --property=MemorySwapMax)"
for expected_limit in MemoryHigh=2621440000 MemoryMax=3355443200 MemorySwapMax=536870912; do
  if ! grep --fixed-strings --quiet "${expected_limit}" <<<"${local_model_limits}"; then
    printf 'Temporary local-model cgroup policy is not effective: %s\n' \
      "${expected_limit}" >&2
    exit 70
  fi
done
wait_for_http "http://127.0.0.1:${local_model_port}/health" 60 1

set +e
response="$(run_as_restored_hermes env \
  PYTHONPATH=/usr/local/lib/hermes-agent \
  PERSISTENCE_MARKER="${marker}" \
  PERSISTENCE_MODEL_ID="${model_id}" \
  PERSISTENCE_TIMEOUT_SECONDS="${provider_timeout_seconds}" \
  /usr/local/lib/hermes-agent/venv/bin/python - 2>"${provider_stderr_file}" <<'PY'
import os
from pathlib import Path

from hermes_cli.runtime_provider import resolve_runtime_provider
from openai import OpenAI

marker = os.environ["PERSISTENCE_MARKER"]
model_id = os.environ["PERSISTENCE_MODEL_ID"]
timeout_seconds = int(os.environ["PERSISTENCE_TIMEOUT_SECONDS"])
memory_path = Path(os.environ["HERMES_HOME"]) / "memories" / "MEMORY.md"

if marker not in memory_path.read_text(encoding="utf-8"):
    raise RuntimeError("restored memory marker is unavailable")

runtime = resolve_runtime_provider(
    requested="custom:piserv-persistence-proof",
    target_model=model_id,
)
if runtime.get("provider") != "custom":
    raise RuntimeError("restored provider did not resolve as custom")
if runtime.get("api_mode") != "chat_completions":
    raise RuntimeError("restored provider did not resolve as chat_completions")
if runtime.get("base_url") != "http://127.0.0.1:18083/v1":
    raise RuntimeError("restored provider did not resolve to the test endpoint")

client = OpenAI(
    api_key=runtime["api_key"],
    base_url=runtime["base_url"],
    timeout=timeout_seconds,
)
completion = client.chat.completions.create(
    model=runtime.get("model") or model_id,
    messages=[
        {"role": "system", "content": "Return only the supplied marker."},
        {"role": "user", "content": marker},
    ],
    max_tokens=32,
)
print(completion.choices[0].message.content or "")
PY
)"
provider_status=$?
set -e

if (( provider_status != 0 )); then
  {
    printf 'Restored provider migration invocation failed with exit status %s.\n' \
      "${provider_status}"
    if [[ -s "${provider_stderr_file}" ]]; then
      printf 'Provider invocation diagnostic: '
      /usr/bin/python3 - "${provider_stderr_file}" <<'PY'
import re
import sys

line = open(sys.argv[1], encoding="utf-8").readline().strip()
line = re.sub(
    r"(?i)(api[_ -]?key|token|authorization|bearer)(?:=|:|\s+)\S+",
    r"\1=[REDACTED]",
    line,
)
print(line[:512])
PY
    fi
  } | systemd-cat --identifier=hermes-persistence-proof --priority=err
  exit 74
fi

if [[ "${response}" != *"${marker}"* ]]; then
  printf 'Restored local-provider response did not contain the persistence marker.\n' >&2
  exit 74
fi

if [[ -f "${source_home}/memories/MEMORY.md" ]] && \
  grep --fixed-strings --quiet "${marker}" "${source_home}/memories/MEMORY.md"; then
  printf 'The persistence marker leaked into the source Hermes memory.\n' >&2
  exit 74
fi
test ! -e "${source_home}/skills/piserv-persistence-proof"
systemctl is-active --quiet "${dashboard_service}"

printf 'persistence_proof=passed\n'
printf 'marker=%s\n' "${marker}"
printf 'stage_backup_bytes=%s\n' "${stage_archive_bytes}"
printf 'stage_backup_sha256=%s\n' "${stage_archive_sha256}"
REMOTE
start_status=$?
set -e

wait_for_proof_result() {
  local attempt
  local status_output
  local active_state
  local result
  local main_status

  attempt=0
  while (( attempt < 300 )); do
    status_output="$(ssh -o BatchMode=yes "${target}" \
      "systemctl show ${unit_name}.service --property=ActiveState --property=Result --property=ExecMainStatus")" || true
    active_state="$(awk -F= '$1 == "ActiveState" { print $2 }' <<<"${status_output}")"
    result="$(awk -F= '$1 == "Result" { print $2 }' <<<"${status_output}")"
    main_status="$(awk -F= '$1 == "ExecMainStatus" { print $2 }' <<<"${status_output}")"

    if [[ "${active_state}" != active && "${active_state}" != activating ]]; then
      if [[ "${result}" == success && "${main_status}" == 0 ]]; then
        printf 'persistence_proof=passed\n'
        return 0
      fi

      printf 'persistence_proof=failed result=%s main_status=%s\n' \
        "${result:-unknown}" "${main_status:-unknown}" >&2
      ssh -o BatchMode=yes "${target}" \
        "journalctl --no-pager -o cat -u ${unit_name}.service -n 80" >&2 || true
      return 1
    fi

    sleep 2
    ((attempt += 1))
  done

  printf 'persistence_proof=timed_out\n' >&2
  return 1
}

if (( start_status != 0 )); then
  printf 'Transient proof launcher returned status %s; checking remote result.\n' \
    "${start_status}" >&2
fi

wait_for_proof_result
