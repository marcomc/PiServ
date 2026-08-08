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

if [[ ! "${api_url}" =~ ^http://[A-Za-z0-9.-]+:[0-9]+/api$ ]]; then
  printf 'Unsupported Home Assistant API URL in %s\n' "${config_path}" >&2
  exit 64
fi
if [[ ! "${entity_id}" =~ ^(light|switch)\.[a-z0-9_]+$ ]]; then
  printf 'Unsupported reversible test entity in %s\n' "${config_path}" >&2
  exit 64
fi

target="$(piserv_ssh_target)"
unit_name="hermes-home-assistant-restore-proof-$(date -u +%Y%m%d%H%M%S)"

printf 'Starting isolated MCP backup-restore proof unit: %s\n' "${unit_name}"
ssh -o BatchMode=yes "${target}" \
  "sudo systemd-run --unit='${unit_name}' --wait --pipe --service-type=exec --property=RuntimeMaxSec=15min --setenv='HOME_ASSISTANT_API_URL=${api_url}' --setenv='HOME_ASSISTANT_ENTITY=${entity_id}' /bin/bash -s" <<'REMOTE'
set -euo pipefail

source_home=/var/lib/hermes-agent
source_codex_home="${source_home}/codex"
token_env_file="${source_home}/home-assistant-mcp.env"
api_url="${HOME_ASSISTANT_API_URL:?HOME_ASSISTANT_API_URL is required}"
entity_id="${HOME_ASSISTANT_ENTITY:?HOME_ASSISTANT_ENTITY is required}"
timestamp="$(date --utc +%Y%m%dT%H%M%SZ)"
work_dir="$(mktemp -d /run/hermes-home-assistant-restore.XXXXXX)"
backup_dir="${work_dir}/backup"
restore_home="${work_dir}/restore"
initial_state=""
restore_required=false

cleanup() {
  local status=$?
  local cleanup_status=0

  if [[ "${restore_required}" == true && -n "${initial_state}" ]]; then
    if [[ "$(home_assistant_state)" != "${initial_state}" ]]; then
      restore_prompt="Hermes backup-restore MCP emergency cleanup ${timestamp}. Use only the home-assistant-assist MCP server. Restore only ${entity_id} to ${initial_state}, verify it, and touch nothing else."
      if ! run_as_restored_hermes hermes chat --query "${restore_prompt}" --quiet \
        --toolsets home-assistant-assist --max-turns 20 \
        >"${work_dir}/emergency-restore.log" 2>&1; then
        cleanup_status=70
      elif [[ "$(home_assistant_state)" != "${initial_state}" ]]; then
        cleanup_status=70
      fi
    fi
  fi

  rm -rf -- "${work_dir}"
  if (( status == 0 && cleanup_status != 0 )); then
    status=${cleanup_status}
  fi
  exit "${status}"
}
trap cleanup EXIT

if [[ ! -f "${token_env_file}" ]]; then
  printf 'MCP token environment file is missing.\n' >&2
  exit 65
fi

run_as_source_hermes() {
  runuser -u hermes-agent -- env \
    HOME="${source_home}" \
    HERMES_HOME="${source_home}" \
    CODEX_HOME="${source_codex_home}" \
    "$@"
}

run_as_restored_hermes() {
  runuser -u hermes-agent --preserve-environment -- env \
    HOME="${restore_home}" \
    HERMES_HOME="${restore_home}" \
    CODEX_HOME="${restore_home}/codex" \
    "$@"
}

home_assistant_state() {
  local curl_config

  curl_config="$(mktemp "${work_dir}/curl.XXXXXX")"
  chmod 0600 "${curl_config}"
  printf 'header = "Authorization: Bearer %s"\n' "${HASS_MCP_TOKEN}" >"${curl_config}"
  curl --config "${curl_config}" --fail --silent --show-error --max-time 10 \
    "${api_url}/states/${entity_id}" | jq --raw-output '.state'
  rm -f -- "${curl_config}"
}

set -a
# shellcheck disable=SC1090
source "${token_env_file}"
set +a

if [[ -z "${HASS_MCP_TOKEN:-}" ]]; then
  printf 'MCP token environment file did not define HASS_MCP_TOKEN.\n' >&2
  exit 65
fi

chmod 0711 "${work_dir}"
install -d -o hermes-agent -g hermes-agent -m 0700 \
  "${backup_dir}" "${restore_home}"
run_as_source_hermes hermes backup --output "${backup_dir}" >/dev/null
archive_path="$(find "${backup_dir}" -maxdepth 1 -type f -name 'hermes-backup-*.zip' -print -quit)"
if [[ -z "${archive_path}" ]]; then
  printf 'Hermes backup did not create an archive.\n' >&2
  exit 66
fi

run_as_restored_hermes hermes import --force "${archive_path}" >/dev/null
run_as_restored_hermes hermes mcp test home-assistant-assist \
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
restore_required=true
run_as_restored_hermes hermes chat --query "${action_prompt}" --quiet \
  --toolsets home-assistant-assist --max-turns 20 \
  >"${work_dir}/action.log" 2>&1

if [[ "$(home_assistant_state)" != "${desired_state}" ]]; then
  printf 'Restored Hermes home did not apply the requested state.\n' >&2
  exit 69
fi

restore_prompt="Hermes backup-restore MCP cleanup ${timestamp}. Use only the home-assistant-assist MCP server. Restore only ${entity_id} to ${initial_state}, verify it, and touch nothing else."
run_as_restored_hermes hermes chat --query "${restore_prompt}" --quiet \
  --toolsets home-assistant-assist --max-turns 20 \
  >"${work_dir}/restore.log" 2>&1

if [[ "$(home_assistant_state)" != "${initial_state}" ]]; then
  printf 'Restored Hermes home did not restore the original state.\n' >&2
  exit 70
fi
restore_required=false

printf 'HERMES_HOME_ASSISTANT_BACKUP_RESTORE_OK entity=%s tools=discovered\n' \
  "${entity_id}"
REMOTE
