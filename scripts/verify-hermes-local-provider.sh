#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/piserv-target.sh
source "${script_dir}/lib/piserv-target.sh"
target="$(piserv_ssh_target)"

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: %s MODEL_ID\n' "$0" >&2
  exit 64
fi

model_id=$1
case "${model_id}" in
  gemma-4-e2b|granite-3-3-2b|llama-3-2-1b-instruct) ;;
  *)
    printf 'Unsupported configured local model: %s\n' "${model_id}" >&2
    exit 64
    ;;
esac

unit_name="hermes-local-provider-proof-${model_id}-$(date -u +%Y%m%d%H%M%S)"

printf 'Starting isolated local-provider proof unit: %s\n' "${unit_name}"
ssh -o BatchMode=yes "${target}" \
  "sudo systemd-run --unit='${unit_name}' --wait --pipe --service-type=exec --property=RuntimeMaxSec=20min --property=OOMScoreAdjust=500 --setenv='MODEL_ID=${model_id}' /bin/bash -s" <<'REMOTE'
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
runtime_dropin_dir="/run/systemd/system/${service_name}.d"
runtime_dropin_path=""
runtime_dropin_dir_created=false
service_stopped=false

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

wait_for_model_http() {
  local url=$1
  local attempts=$2
  local delay_seconds=$3
  local attempt

  for attempt in $(seq 1 "${attempts}"); do
    if curl --fail --silent --max-time 5 "${url}" >/dev/null 2>&1; then
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

assert_model_test_preflight() {
  local controllers
  local active_model_service
  local memory_high
  local memory_max
  local memory_swap_max

  controllers="$(< /sys/fs/cgroup/cgroup.controllers)"
  if [[ " ${controllers} " != *' memory '* ]]; then
    printf 'The cgroup v2 memory controller is unavailable.\n' >&2
    exit 70
  fi

  active_model_service="$(systemctl list-units --type=service --state=active \
    --plain --no-legend 'hermes-local-model-*.service' | awk 'NF { print $1; exit }')"
  if [[ -n "${active_model_service}" ]]; then
    printf 'Refusing to run while a local model service is active: %s\n' \
      "${active_model_service}" >&2
    exit 70
  fi

  memory_high="$(systemctl show "${service_name}" --property=MemoryHigh --value)"
  memory_max="$(systemctl show "${service_name}" --property=MemoryMax --value)"
  memory_swap_max="$(systemctl show "${service_name}" --property=MemorySwapMax --value)"
  for memory_limit in "${memory_high}" "${memory_max}" "${memory_swap_max}"; do
    if [[ ! "${memory_limit}" =~ ^[1-9][0-9]*$ ]]; then
      printf 'Local model cgroup memory policy is not effective: %s\n' \
        "${service_name}" >&2
      exit 70
    fi
  done
  if (( memory_high > memory_max )); then
    printf 'Local model cgroup memory policy has MemoryHigh above MemoryMax.\n' >&2
    exit 70
  fi
}

relax_limit_as() {
  local effective_limit_as

  if [[ -L "${runtime_dropin_dir}" ]]; then
    printf 'Refusing symlinked systemd runtime drop-in directory: %s\n' \
      "${runtime_dropin_dir}" >&2
    exit 70
  fi
  if [[ ! -e "${runtime_dropin_dir}" ]]; then
    install -d -o root -g root -m 0755 "${runtime_dropin_dir}"
    runtime_dropin_dir_created=true
  elif [[ ! -d "${runtime_dropin_dir}" ]]; then
    printf 'Systemd runtime drop-in path is not a directory: %s\n' \
      "${runtime_dropin_dir}" >&2
    exit 70
  fi

  runtime_dropin_path="$(mktemp "${runtime_dropin_dir}/90-hermes-local-provider-proof.XXXXXX")"
  printf '%s\n' '[Service]' 'LimitAS=infinity' > "${runtime_dropin_path}"
  chmod 0644 "${runtime_dropin_path}"
  mv -- "${runtime_dropin_path}" "${runtime_dropin_path}.conf"
  runtime_dropin_path="${runtime_dropin_path}.conf"
  systemctl daemon-reload

  effective_limit_as="$(systemctl show "${service_name}" --property=LimitAS --value)"
  if [[ "${effective_limit_as}" != "infinity" ]]; then
    printf 'Unable to relax LimitAS for the controlled local-provider proof.\n' >&2
    exit 70
  fi
}

remove_limit_as_override() {
  if [[ -n "${runtime_dropin_path}" ]]; then
    rm -f -- "${runtime_dropin_path}"
  fi
  if [[ "${runtime_dropin_dir_created}" == true ]]; then
    rmdir "${runtime_dropin_dir}" 2>/dev/null || true
  fi
  if [[ -n "${runtime_dropin_path}" || "${runtime_dropin_dir_created}" == true ]]; then
    systemctl daemon-reload
  fi
}

cleanup() {
  local status=$?

  if [[ "${service_stopped}" != true ]]; then
    systemctl stop "${service_name}" >/dev/null 2>&1 || true
  fi
  remove_limit_as_override
  rm -rf -- "${work_dir}"
  exit "${status}"
}
trap cleanup EXIT

if ! systemctl cat "${service_name}" >/dev/null; then
  printf 'Configured local model service is unavailable: %s\n' "${service_name}" >&2
  exit 65
fi

assert_model_test_preflight
relax_limit_as

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

model_control_group="$(systemctl show "${service_name}" --property=ControlGroup --value)"
if [[ ! "${model_control_group}" =~ ^/system\.slice/hermes-local-model-[a-z0-9-]+\.service$ ]]; then
  printf 'Unexpected local model control group: %s\n' "${model_control_group}" >&2
  exit 70
fi

cgroup_directory="/sys/fs/cgroup${model_control_group}"
for cgroup_file in memory.current memory.events memory.swap.current; do
  if [[ ! -r "${cgroup_directory}/${cgroup_file}" ]]; then
    printf 'Missing cgroup memory accounting file: %s\n' \
      "${cgroup_directory}/${cgroup_file}" >&2
    exit 70
  fi
done

main_pid="$(systemctl show "${service_name}" --property=MainPID --value)"
if [[ ! "${main_pid}" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Unable to determine local model main PID: %s\n' "${main_pid}" >&2
  exit 70
fi

memory_current_before="$(<"${cgroup_directory}/memory.current")"
memory_swap_current_before="$(<"${cgroup_directory}/memory.swap.current")"
memory_events_before="$(jq --raw-input 'split("\n") | map(select(length > 0) | split(" ") | {key: .[0], value: (.[1] | tonumber)}) | from_entries' < "${cgroup_directory}/memory.events")"
rss_before="$(awk '/VmRSS:/ { print $2 * 1024 }' "/proc/${main_pid}/status")"
swap_used_before="$(awk '/SwapTotal:/ { total = $2 * 1024 } /SwapFree:/ { free = $2 * 1024 } END { print total - free }' /proc/meminfo)"
proof_started_nanoseconds="$(date +%s%N)"

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
proof_finished_nanoseconds="$(date +%s%N)"

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

memory_current_after="$(<"${cgroup_directory}/memory.current")"
memory_swap_current_after="$(<"${cgroup_directory}/memory.swap.current")"
memory_events_after="$(jq --raw-input 'split("\n") | map(select(length > 0) | split(" ") | {key: .[0], value: (.[1] | tonumber)}) | from_entries' < "${cgroup_directory}/memory.events")"
rss_after="$(awk '/VmRSS:/ { print $2 * 1024 }' "/proc/${main_pid}/status")"
swap_used_after="$(awk '/SwapTotal:/ { total = $2 * 1024 } /SwapFree:/ { free = $2 * 1024 } END { print total - free }' /proc/meminfo)"
proof_latency_milliseconds="$(( (proof_finished_nanoseconds - proof_started_nanoseconds) / 1000000 ))"
service_state="$(systemctl show "${service_name}" --property=MemoryCurrent --property=MemoryPeak --property=MemorySwapCurrent --property=ExecMainStatus)"
dashboard_active_state="$(systemctl is-active hermes-agent-dashboard.service || true)"
dashboard_http_status="$(curl --max-time 5 --output /dev/null --silent --write-out '%{http_code}' http://127.0.0.1:9119/ || true)"

systemctl stop "${service_name}"
service_stopped=true
cleanup_active_state="$(systemctl show "${service_name}" --property=ActiveState --value)"

jq --null-input \
  --arg model_id "${model_id}" \
  --arg model_control_group "${model_control_group}" \
  --arg service_state "${service_state}" \
  --arg dashboard_active_state "${dashboard_active_state}" \
  --arg dashboard_http_status "${dashboard_http_status}" \
  --arg cleanup_active_state "${cleanup_active_state}" \
  --argjson proof_latency_milliseconds "${proof_latency_milliseconds}" \
  --argjson memory_current_before "${memory_current_before}" \
  --argjson memory_current_after "${memory_current_after}" \
  --argjson memory_swap_current_before "${memory_swap_current_before}" \
  --argjson memory_swap_current_after "${memory_swap_current_after}" \
  --argjson memory_events_before "${memory_events_before}" \
  --argjson memory_events_after "${memory_events_after}" \
  --argjson rss_before "${rss_before}" \
  --argjson rss_after "${rss_after}" \
  --argjson swap_used_before "${swap_used_before}" \
  --argjson swap_used_after "${swap_used_after}" \
  '{
    model_id: $model_id,
    response_contains_marker: true,
    limit_as_relaxed: true,
    proof_latency_milliseconds: $proof_latency_milliseconds,
    model_control_group: $model_control_group,
    cgroup_memory: {
      current_before: $memory_current_before,
      current_after: $memory_current_after,
      swap_current_before: $memory_swap_current_before,
      swap_current_after: $memory_swap_current_after,
      events_before: $memory_events_before,
      events_after: $memory_events_after
    },
    process_rss_bytes: {
      before: $rss_before,
      after: $rss_after
    },
    host_swap_used_bytes: {
      before: $swap_used_before,
      after: $swap_used_after
    },
    service_state: $service_state,
    dashboard: {
      active_state: $dashboard_active_state,
      http_status: $dashboard_http_status
    },
    cleanup: {
      active_state: $cleanup_active_state,
      service_stopped: ($cleanup_active_state == "inactive")
    }
  }'
REMOTE
