#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/piserv-target.sh
source "${script_dir}/lib/piserv-target.sh"

config_path=${1:-"${script_dir}/hermes-home-apple-home.local.json"}

if [[ ! -f "${config_path}" ]]; then
  printf 'Configuration file not found: %s\n' "${config_path}" >&2
  exit 64
fi

api_url="$(jq --raw-output '.home_assistant_api_url' "${config_path}")"
entity_id="$(jq --raw-output '.entities[0].home_assistant_entity_id' "${config_path}")"
risk="$(jq --raw-output '.entities[0].risk // empty' "${config_path}")"

if [[ ! "${api_url}" =~ ^http://[A-Za-z0-9.-]+:[0-9]+/api$ ]]; then
  printf 'Unsupported Home Assistant API URL in %s\n' "${config_path}" >&2
  exit 64
fi
if [[ ! "${entity_id}" =~ ^(light|switch)\.[a-z0-9_]+$ ]]; then
  printf 'Unsupported reversible test entity in %s\n' "${config_path}" >&2
  exit 64
fi
if [[ "${risk}" != non-critical ]]; then
  printf 'The first configured entity must explicitly declare risk=non-critical.\n' >&2
  exit 64
fi

target="$(piserv_ssh_target)"
unit_name="hermes-home-assistant-restore-proof-$(date -u +%Y%m%d%H%M%S)-$$"
audit_helper_remote="/run/${unit_name}-audit.py"
outer_runtime_seconds=1200
outer_stop_seconds=300
ssh_options=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=2
)
helper_staged=false
unit_launch_attempted=false

cleanup_remote_launch() {
  local primary_status=$?
  local cleanup_status=0

  trap - EXIT INT TERM
  if [[ "${unit_launch_attempted}" == true || "${helper_staged}" == true ]]; then
    # The validated local unit and helper names are intentionally expanded here.
    # shellcheck disable=SC2029
    if ! ssh "${ssh_options[@]}" "${target}" \
      "sudo timeout --kill-after=5s 30s /bin/bash -c 'systemctl stop \"${unit_name}.service\" 2>/dev/null || true; systemctl reset-failed \"${unit_name}.service\" 2>/dev/null || true; rm -f -- \"${audit_helper_remote}\"'"; then
      cleanup_status=71
      printf 'Launch cleanup failed for unit %s and helper %s.\n' \
        "${unit_name}" "${audit_helper_remote}" >&2
    fi
  fi
  if (( primary_status == 0 && cleanup_status != 0 )); then
    primary_status=${cleanup_status}
  fi
  exit "${primary_status}"
}
trap cleanup_remote_launch EXIT INT TERM

# The validated local helper path is intentionally expanded here.
# shellcheck disable=SC2029
ssh "${ssh_options[@]}" "${target}" \
  "sudo install -o root -g root -m 0600 /dev/stdin '${audit_helper_remote}'" \
  <"${script_dir}/hermes_audit.py"
helper_staged=true

printf 'Starting isolated MCP backup-restore proof unit: %s\n' "${unit_name}"
unit_launch_attempted=true
# The validated local unit, API, entity, and helper values are expanded here.
# shellcheck disable=SC2029
ssh "${ssh_options[@]}" "${target}" \
  "sudo systemd-run --unit='${unit_name}' --wait --pipe --service-type=exec --property=RuntimeMaxSec=${outer_runtime_seconds}s --property=TimeoutStopSec=${outer_stop_seconds}s --setenv='HOME_ASSISTANT_API_URL=${api_url}' --setenv='HOME_ASSISTANT_ENTITY=${entity_id}' --setenv='HERMES_AUDIT_HELPER=${audit_helper_remote}' /bin/bash -s" <<'REMOTE'
set -euo pipefail

source_home=/var/lib/hermes-agent
source_codex_home="${source_home}/codex"
token_env_file="${source_home}/home-assistant-mcp.env"
managed_policy=/etc/hermes-agent/policies/smart-home-AGENTS.md
managed_config=/usr/local/lib/hermes-agent/.hermes-config.yaml
audit_helper="${HERMES_AUDIT_HELPER:?HERMES_AUDIT_HELPER is required}"
api_url="${HOME_ASSISTANT_API_URL:?HOME_ASSISTANT_API_URL is required}"
entity_id="${HOME_ASSISTANT_ENTITY:?HOME_ASSISTANT_ENTITY is required}"
timestamp="$(date --utc +%Y%m%dT%H%M%SZ)"
work_dir="$(mktemp -d /run/hermes-home-assistant-restore.XXXXXX)"
backup_stage="${work_dir}/backup-stage"
evidence_dir="${work_dir}/evidence"
restore_home="${work_dir}/restore"
initial_state=""
restore_required=false
primary_deadline_seconds=600
operation_timeout_seconds=60
deadline_pid=""

on_primary_deadline() {
  printf 'Primary acceptance deadline exceeded; starting emergency cleanup.\n' >&2
  exit 124
}

trap on_primary_deadline TERM

cleanup() {
  local primary_status=$?
  local cleanup_status=0

  if [[ "${restore_required}" == true && -n "${initial_state}" ]]; then
    if [[ "$(home_assistant_state)" != "${initial_state}" ]]; then
      restore_prompt="Hermes backup-restore MCP emergency cleanup ${timestamp}. Use only the home-assistant-assist MCP server. Restore only ${entity_id} to ${initial_state}, verify it, and touch nothing else."
      emergency_source="piserv-backup-restore-emergency-${timestamp}-$$"
      if ! run_protected_hermes "${restore_home}" "${emergency_source}" \
        chat --query "${restore_prompt}" --quiet \
        --toolsets home-assistant-assist --max-turns 20 --source "${emergency_source}" \
        >"${work_dir}/emergency-restore.log" 2>&1; then
        cleanup_status=70
      elif ! export_and_validate_audit \
        "${restore_home}" "${emergency_source}" "emergency restoration"; then
        cleanup_status=70
      elif [[ "$(home_assistant_state)" != "${initial_state}" ]]; then
        cleanup_status=70
      fi
    fi
  fi

  if [[ -n "${deadline_pid}" ]]; then
    kill "${deadline_pid}" 2>/dev/null || true
    wait "${deadline_pid}" 2>/dev/null || true
  fi

  if (( cleanup_status != 0 )); then
    timeout --kill-after=5s 30s \
      setfacl --remove user:hermes-agent "${work_dir}" 2>/dev/null || true
    timeout --kill-after=5s 30s chown -R root:root "${work_dir}"
    timeout --kill-after=5s 30s chmod -R go-rwx "${work_dir}"
    printf 'Emergency restoration failed; work directory preserved for inspection: %s\n' \
      "${work_dir}" >&2
  else
    timeout --kill-after=5s 30s rm -rf -- "${work_dir}"
  fi
  timeout --kill-after=5s 30s rm -f -- "${audit_helper}"
  if (( primary_status != 0 )); then
    printf 'Primary acceptance failure status: %d\n' "${primary_status}" >&2
  fi
  if (( cleanup_status != 0 )); then
    printf 'Cleanup failure status: %d\n' "${cleanup_status}" >&2
  fi
  if (( primary_status == 0 && cleanup_status != 0 )); then
    primary_status=${cleanup_status}
  fi
  exit "${primary_status}"
}
trap cleanup EXIT
umask 077
(sleep "${primary_deadline_seconds}"; kill -TERM "$$") &
deadline_pid=$!

if [[ ! -f "${token_env_file}" ]]; then
  printf 'MCP token environment file is missing.\n' >&2
  exit 65
fi

run_as_source_hermes() {
  timeout --signal=TERM --kill-after=10s "${operation_timeout_seconds}" \
    runuser -u hermes-agent -- env \
    HOME="${source_home}" \
    HERMES_HOME="${source_home}" \
    CODEX_HOME="${source_codex_home}" \
    "$@"
}

run_as_restored_hermes() {
  timeout --signal=TERM --kill-after=10s "${operation_timeout_seconds}" \
    runuser -u hermes-agent --preserve-environment -- env \
    HOME="${restore_home}" \
    HERMES_HOME="${restore_home}" \
    CODEX_HOME="${restore_home}/codex" \
    bash -c 'cd -- "${HERMES_HOME}/workspace" && exec "$@"' bash "$@"
}

run_protected_hermes() {
  local hermes_home=$1
  shift 2
  local workspace="${hermes_home}/workspace"
  local codex_home="${hermes_home}/codex"

  test -f "${managed_policy}"
  test -f "${managed_config}"
  test -e "${hermes_home}/config.yaml"
  if [[ ! -e "${workspace}/AGENTS.md" ]]; then
    install -o hermes-agent -g hermes-agent -m 0600 /dev/null \
      "${workspace}/AGENTS.md"
  fi
  systemd-run --quiet --wait --pipe --collect --service-type=exec \
    --uid=hermes-agent \
    --property=RuntimeMaxSec=1min \
    --property=NoNewPrivileges=yes \
    --property=PrivateTmp=yes \
    --property=ProtectSystem=strict \
    --property=ProtectHome=yes \
    --property="ReadWritePaths=${hermes_home}" \
    --property="BindReadOnlyPaths=${managed_config}:${hermes_home}/config.yaml" \
    --property="EnvironmentFile=${token_env_file}" \
    --property="BindReadOnlyPaths=${managed_policy}:${workspace}/AGENTS.md" \
    --property="RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6" \
    --setenv="HOME=${hermes_home}" \
    --setenv="HERMES_HOME=${hermes_home}" \
    --setenv="CODEX_HOME=${codex_home}" \
    --working-directory="${workspace}" \
    -- hermes "$@"
}

export_and_validate_audit() {
  local hermes_home=$1
  local source_tag=$2
  local label=$3
  local export_path="${work_dir}/${source_tag}.jsonl"

  run_protected_hermes "${hermes_home}" "${source_tag}" \
    sessions export - --format jsonl --source "${source_tag}" \
    --newer-than 5m --redact >"${export_path}"
  timeout --signal=TERM --kill-after=10s "${operation_timeout_seconds}" \
    python3 "${audit_helper}" --export "${export_path}" \
    --source "${source_tag}" --entity "${entity_id}" --label "${label}"
}

load_hass_mcp_token() {
  local line
  local assignment_count=0

  HASS_MCP_TOKEN=""
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ^HASS_MCP_TOKEN=([A-Za-z0-9._~-]+)$ ]]; then
      ((assignment_count += 1))
      HASS_MCP_TOKEN="${BASH_REMATCH[1]}"
      continue
    fi
    printf 'MCP token environment file must contain only one data assignment.\n' >&2
    return 65
  done <"${token_env_file}"

  if (( assignment_count != 1 )) || [[ -z "${HASS_MCP_TOKEN}" ]]; then
    printf 'MCP token environment file must define HASS_MCP_TOKEN exactly once.\n' >&2
    return 65
  fi
  export HASS_MCP_TOKEN
}

home_assistant_state() {
  local curl_config
  local response

  curl_config="$(mktemp "${work_dir}/curl.XXXXXX")"
  chmod 0600 "${curl_config}"
  printf 'header = "Authorization: Bearer %s"\n' "${HASS_MCP_TOKEN}" >"${curl_config}"
  response="$(timeout --signal=TERM --kill-after=2s 15s \
    curl --config "${curl_config}" --fail --silent --show-error --max-time 10 \
    "${api_url}/states/${entity_id}")"
  rm -f -- "${curl_config}"
  timeout --signal=TERM --kill-after=2s 15s \
    jq --raw-output '.state' <<<"${response}"
}

load_hass_mcp_token

setfacl --modify user:hermes-agent:--x "${work_dir}"
install -d -o hermes-agent -g hermes-agent -m 0700 \
  "${backup_stage}" "${restore_home}" "${restore_home}/workspace"
install -d -o root -g root -m 0700 "${evidence_dir}"
run_protected_hermes "${source_home}" "backup" \
  backup --output "${backup_stage}" >/dev/null
staged_archive="$(find "${backup_stage}" -maxdepth 1 -type f -name 'hermes-backup-*.zip' -print -quit)"
if [[ -z "${staged_archive}" ]]; then
  printf 'Hermes backup did not create an archive.\n' >&2
  exit 66
fi
archive_path="${evidence_dir}/$(basename -- "${staged_archive}")"
install -o root -g root -m 0600 "${staged_archive}" "${archive_path}"
install -o hermes-agent -g hermes-agent -m 0600 \
  "${archive_path}" "${restore_home}/hermes-backup.zip"
rm -rf -- "${backup_stage}"

run_as_restored_hermes hermes import --force \
  "${restore_home}/hermes-backup.zip" >/dev/null
rm -f -- "${restore_home}/hermes-backup.zip"
run_protected_hermes "${restore_home}" "mcp-test" \
  mcp test home-assistant-assist \
  >"${work_dir}/mcp-test.log" 2>&1

if ! grep --fixed-strings --quiet 'Tools discovered:' "${work_dir}/mcp-test.log"; then
  printf 'Restored Hermes home did not discover Home Assistant MCP tools.\n' >&2
  exit 67
fi

initial_state="$(home_assistant_state)"
case "${initial_state}" in
  on)
    desired_state=off
    ;;
  off)
    desired_state=on
    ;;
  *)
    printf 'Test entity is not in a reversible on/off state: %s\n' \
      "${initial_state}" >&2
    exit 68
    ;;
esac

action_prompt="Hermes backup-restore MCP acceptance test ${timestamp}. Use only the home-assistant-assist MCP server. You are authorized to change only ${entity_id} to ${desired_state}, verify its state, and touch nothing else."
action_source="piserv-backup-restore-action-${timestamp}-$$"
restore_required=true
run_protected_hermes "${restore_home}" "${action_source}" \
  chat --query "${action_prompt}" --quiet \
  --toolsets home-assistant-assist --max-turns 20 --source "${action_source}" \
  >"${work_dir}/action.log" 2>&1
export_and_validate_audit \
  "${restore_home}" "${action_source}" "backup-restore action"

if [[ "$(home_assistant_state)" != "${desired_state}" ]]; then
  printf 'Restored Hermes home did not apply the requested state.\n' >&2
  exit 69
fi

restore_prompt="Hermes backup-restore MCP cleanup ${timestamp}. Use only the home-assistant-assist MCP server. Restore only ${entity_id} to ${initial_state}, verify it, and touch nothing else."
restore_source="piserv-backup-restore-cleanup-${timestamp}-$$"
run_protected_hermes "${restore_home}" "${restore_source}" \
  chat --query "${restore_prompt}" --quiet \
  --toolsets home-assistant-assist --max-turns 20 --source "${restore_source}" \
  >"${work_dir}/restore.log" 2>&1
export_and_validate_audit \
  "${restore_home}" "${restore_source}" "backup-restore cleanup"

if [[ "$(home_assistant_state)" != "${initial_state}" ]]; then
  printf 'Restored Hermes home did not restore the original state.\n' >&2
  exit 70
fi
restore_required=false

printf 'HERMES_HOME_ASSISTANT_BACKUP_RESTORE_OK entity=%s tools=discovered\n' \
  "${entity_id}"
REMOTE
