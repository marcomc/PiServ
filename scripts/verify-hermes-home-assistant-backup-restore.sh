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
proof_run_id="$(date -u +%Y%m%d%H%M%S)-$$"
if [[ ! "${proof_run_id}" =~ ^[0-9]{14}-[0-9]+$ ]]; then
  printf 'Generated proof-run identifier is invalid: %s\n' "${proof_run_id}" >&2
  exit 64
fi
unit_name="hermes-home-assistant-restore-proof-${proof_run_id}"
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
foreground_ssh_pid=""
foreground_ssh_term_grace_attempts=20

terminate_foreground_ssh() {
  local attempt
  local pid=${foreground_ssh_pid}

  if [[ -z "${pid}" ]]; then
    return 0
  fi

  kill -TERM "${pid}" 2>/dev/null || true
  for (( attempt = 0; attempt < foreground_ssh_term_grace_attempts; attempt++ )); do
    if ! kill -0 "${pid}" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  if kill -0 "${pid}" 2>/dev/null; then
    kill -KILL "${pid}" 2>/dev/null || true
  fi
  wait "${pid}" 2>/dev/null || true
  foreground_ssh_pid=""
}

interrupt_remote_launch() {
  local signal_status=$1

  trap - INT TERM
  terminate_foreground_ssh
  cleanup_remote_launch "${signal_status}"
}

cleanup_remote_launch() {
  local primary_status=${1:-$?}
  local cleanup_status=0

  trap - EXIT INT TERM
  if [[ "${unit_launch_attempted}" == true || "${helper_staged}" == true ]]; then
    # The validated local unit and helper names are intentionally expanded here.
    # shellcheck disable=SC2029
    if ! ssh "${ssh_options[@]}" "${target}" \
      "sudo timeout --kill-after=5s 30s /bin/bash -c 'cleanup_status=0; systemctl stop \"${unit_name}.service\" || cleanup_status=72; state=; for _attempt in {1..20}; do state=\$(systemctl show \"${unit_name}.service\" --property=ActiveState --value) || { cleanup_status=73; break; }; case \${state} in inactive|failed) break ;; esac; sleep 1; done; case \${state} in inactive|failed) ;; *) cleanup_status=73 ;; esac; systemctl reset-failed \"${unit_name}.service\" || { test \${cleanup_status} -ne 0 || cleanup_status=74; }; rm -f -- \"${audit_helper_remote}\" || { test \${cleanup_status} -ne 0 || cleanup_status=75; }; exit \${cleanup_status}'"; then
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
trap cleanup_remote_launch EXIT
trap 'interrupt_remote_launch 130' INT
trap 'interrupt_remote_launch 143' TERM

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
  "sudo systemd-run --unit='${unit_name}' --wait --pipe --service-type=exec --property=RuntimeMaxSec=${outer_runtime_seconds}s --property=TimeoutStopSec=${outer_stop_seconds}s --setenv='PROOF_RUN_ID=${proof_run_id}' --setenv='HOME_ASSISTANT_API_URL=${api_url}' --setenv='HOME_ASSISTANT_ENTITY=${entity_id}' --setenv='HERMES_AUDIT_HELPER=${audit_helper_remote}' /bin/bash -s" <<'REMOTE' &
set -euo pipefail

source_home=/var/lib/hermes-agent
source_codex_home="${source_home}/codex"
token_env_file="${source_home}/home-assistant-mcp.env"
managed_policy=/etc/hermes-agent/policies/smart-home-AGENTS.md
managed_config=/usr/local/lib/hermes-agent/.hermes-config.yaml
audit_helper="${HERMES_AUDIT_HELPER:?HERMES_AUDIT_HELPER is required}"
api_url="${HOME_ASSISTANT_API_URL:?HOME_ASSISTANT_API_URL is required}"
entity_id="${HOME_ASSISTANT_ENTITY:?HOME_ASSISTANT_ENTITY is required}"
proof_run_id="${PROOF_RUN_ID:?PROOF_RUN_ID is required}"
if [[ ! "${proof_run_id}" =~ ^[0-9]{14}-[0-9]+$ ]]; then
  printf 'Proof-run identifier has an invalid format: %s\n' "${proof_run_id}" >&2
  exit 64
fi
timestamp="$(date --utc +%Y%m%dT%H%M%SZ)"
work_dir="$(mktemp -d /run/hermes-home-assistant-restore.XXXXXX)"
backup_stage="${work_dir}/backup-stage"
evidence_dir="${work_dir}/evidence"
restore_home="${work_dir}/restore"
restored_config="${evidence_dir}/restored-config.yaml"
initial_state=""
restore_required=false
primary_deadline_seconds=600
operation_timeout_seconds=60
deadline_pid=""
active_inner_unit=""
inner_unit_sequence=0

on_primary_deadline() {
  printf 'Primary acceptance deadline exceeded; starting emergency cleanup.\n' >&2
  exit 124
}

trap on_primary_deadline TERM

stop_active_inner_unit() {
  local unit=${active_inner_unit}

  if [[ -z "${unit}" ]]; then
    return 0
  fi
  if ! timeout --kill-after=5s 30s systemctl stop "${unit}.service"; then
    printf 'Failed to stop nested Hermes unit %s before restoration.\n' \
      "${unit}" >&2
    return 1
  fi
  if systemctl is-active --quiet "${unit}.service"; then
    printf 'Nested Hermes unit %s remained active after stop.\n' "${unit}" >&2
    return 1
  fi
  systemctl reset-failed "${unit}.service" 2>/dev/null || true
  active_inner_unit=""
}

cleanup() {
  local primary_status=$?
  local cleanup_status=0

  if ! stop_active_inner_unit; then
    cleanup_status=70
  elif [[ "${restore_required}" == true && -n "${initial_state}" ]]; then
    if [[ "$(home_assistant_state)" != "${initial_state}" ]]; then
      restore_prompt="Hermes backup-restore MCP emergency cleanup ${timestamp}. Use only the home-assistant-assist MCP server. Restore only ${entity_id} to ${initial_state}, verify it, and touch nothing else."
      emergency_source="piserv-backup-restore-emergency-${timestamp}-$$"
      if ! run_protected_hermes \
        "${restore_home}" "${emergency_source}" "${restored_config}" "" \
        chat --query "${restore_prompt}" --quiet \
        --toolsets home-assistant-assist --max-turns 20 --source "${emergency_source}" \
        >"${work_dir}/emergency-restore.log" 2>&1; then
        cleanup_status=70
      elif ! export_and_validate_audit \
        "${restore_home}" "${emergency_source}" "emergency restoration" \
        "${initial_state}"; then
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
  local source_tag=$2
  local config_artifact=$3
  local writable_path=$4
  local command_status
  local read_write_paths=${hermes_home}
  shift 4
  local workspace="${hermes_home}/workspace"
  local codex_home="${hermes_home}/codex"

  test -f "${managed_policy}"
  test -f "${config_artifact}"
  test ! -L "${config_artifact}"
  test "$(realpath -e -- "${config_artifact}")" = "${config_artifact}"
  test "$(stat -c '%U:%G:%a' -- "${config_artifact}")" = \
    'root:hermes-agent:640'
  test -e "${hermes_home}/config.yaml"
  if [[ -n "${writable_path}" ]]; then
    test "${writable_path}" = "${backup_stage}"
    test -d "${writable_path}"
    test ! -L "${writable_path}"
    test "$(realpath -e -- "${writable_path}")" = "${writable_path}"
    test "$(stat -c '%U:%G:%a' -- "${writable_path}")" = \
      'hermes-agent:hermes-agent:700'
    read_write_paths+=" ${writable_path}"
  fi
  if [[ ! -e "${workspace}/AGENTS.md" ]]; then
    install -o hermes-agent -g hermes-agent -m 0600 /dev/null \
      "${workspace}/AGENTS.md"
  fi
  ((inner_unit_sequence += 1))
  active_inner_unit="hermes-restore-proof-${proof_run_id}-${inner_unit_sequence}"
  if systemd-run --quiet --wait --pipe --collect --service-type=exec \
    --unit="${active_inner_unit}" \
    --uid=hermes-agent \
    --property=RuntimeMaxSec=1min \
    --property=NoNewPrivileges=yes \
    --property=PrivateTmp=yes \
    --property=ProtectSystem=strict \
    --property=ProtectHome=yes \
    --property="ReadWritePaths=${read_write_paths}" \
    --property="BindReadOnlyPaths=${config_artifact}:${hermes_home}/config.yaml" \
    --property="EnvironmentFile=${token_env_file}" \
    --property="BindReadOnlyPaths=${managed_policy}:${workspace}/AGENTS.md" \
    --property="RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6" \
    --setenv="HOME=${hermes_home}" \
    --setenv="HERMES_HOME=${hermes_home}" \
    --setenv="CODEX_HOME=${codex_home}" \
    --working-directory="${workspace}" \
    -- hermes "$@"; then
    command_status=0
  else
    command_status=$?
  fi
  # systemd-run --wait has proven normal quiescence; cleanup handles interruption.
  active_inner_unit=""
  return "${command_status}"
}

export_and_validate_audit() {
  local hermes_home=$1
  local source_tag=$2
  local label=$3
  local expected_state=$4
  local export_path="${work_dir}/${source_tag}.jsonl"

  run_protected_hermes \
    "${hermes_home}" "${source_tag}" "${restored_config}" "" \
    sessions export - --format jsonl --source "${source_tag}" \
    --newer-than 5m --redact >"${export_path}"
  timeout --signal=TERM --kill-after=10s "${operation_timeout_seconds}" \
    python3 "${audit_helper}" --export "${export_path}" \
    --source "${source_tag}" --entity "${entity_id}" --label "${label}" \
    --expected-state "${expected_state}"
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
run_protected_hermes \
  "${source_home}" "backup" "${managed_config}" "${backup_stage}" \
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
imported_config="${restore_home}/config.yaml"
if [[ ! -f "${imported_config}" || -L "${imported_config}" ]] || \
  [[ "$(realpath -e -- "${imported_config}")" != "${imported_config}" ]] || \
  [[ "$(stat -c '%U:%G' -- "${imported_config}")" != \
  'hermes-agent:hermes-agent' ]]; then
  printf 'Imported Hermes configuration is absent or has unsafe provenance.\n' >&2
  exit 67
fi
if [[ "$(realpath -m -- "${restored_config}")" == "${imported_config}" ]]; then
  printf 'Imported and protected Hermes configuration paths must be distinct.\n' >&2
  exit 67
fi
install -o root -g hermes-agent -m 0640 \
  "${imported_config}" "${restored_config}"
if [[ "$(stat -c '%d:%i' -- "${imported_config}")" == \
  "$(stat -c '%d:%i' -- "${restored_config}")" ]] || \
  ! cmp --silent -- "${imported_config}" "${restored_config}"; then
  printf 'Protected restored configuration differs from the imported source.\n' >&2
  exit 67
fi
run_protected_hermes \
  "${restore_home}" "mcp-test" "${restored_config}" "" \
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
run_protected_hermes \
  "${restore_home}" "${action_source}" "${restored_config}" "" \
  chat --query "${action_prompt}" --quiet \
  --toolsets home-assistant-assist --max-turns 20 --source "${action_source}" \
  >"${work_dir}/action.log" 2>&1
export_and_validate_audit \
  "${restore_home}" "${action_source}" "backup-restore action" \
  "${desired_state}"

if [[ "$(home_assistant_state)" != "${desired_state}" ]]; then
  printf 'Restored Hermes home did not apply the requested state.\n' >&2
  exit 69
fi

restore_prompt="Hermes backup-restore MCP cleanup ${timestamp}. Use only the home-assistant-assist MCP server. Restore only ${entity_id} to ${initial_state}, verify it, and touch nothing else."
restore_source="piserv-backup-restore-cleanup-${timestamp}-$$"
run_protected_hermes \
  "${restore_home}" "${restore_source}" "${restored_config}" "" \
  chat --query "${restore_prompt}" --quiet \
  --toolsets home-assistant-assist --max-turns 20 --source "${restore_source}" \
  >"${work_dir}/restore.log" 2>&1
export_and_validate_audit \
  "${restore_home}" "${restore_source}" "backup-restore cleanup" \
  "${initial_state}"

if [[ "$(home_assistant_state)" != "${initial_state}" ]]; then
  printf 'Restored Hermes home did not restore the original state.\n' >&2
  exit 70
fi
restore_required=false

printf 'HERMES_HOME_ASSISTANT_BACKUP_RESTORE_OK entity=%s tools=discovered\n' \
  "${entity_id}"
REMOTE
foreground_ssh_pid=$!
launch_status=0
wait "${foreground_ssh_pid}" || launch_status=$?
foreground_ssh_pid=""
if (( launch_status != 0 )); then
  exit "${launch_status}"
fi
