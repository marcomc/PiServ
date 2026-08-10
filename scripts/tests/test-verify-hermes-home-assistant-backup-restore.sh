#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
script_path="${repo_root}/scripts/verify-hermes-home-assistant-backup-restore.sh"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "${test_dir}"' EXIT

assert_count() {
  local expected=$1
  local pattern=$2
  local actual

  actual="$(grep --fixed-strings --count -- "${pattern}" "${script_path}")"
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'Expected %s occurrences of %s, found %s.\n' \
      "${expected}" "${pattern}" "${actual}" >&2
    return 1
  fi
}

assert_count 5 "--source \"\${"
assert_count 4 'export_and_validate_audit'
assert_count 1 "--property=\"BindReadOnlyPaths=\${managed_policy}:\${workspace}/AGENTS.md\""
assert_count 1 '--property=ProtectSystem=strict'
assert_count 1 'Primary acceptance failure status:'
assert_count 1 'Cleanup failure status:'
assert_count 1 'primary_deadline_seconds=600'
assert_count 1 'outer_runtime_seconds=1200'
assert_count 1 'outer_stop_seconds=300'
assert_count 1 "--property=RuntimeMaxSec=\${outer_runtime_seconds}s"
assert_count 1 "--property=TimeoutStopSec=\${outer_stop_seconds}s"
assert_count 1 'trap cleanup_remote_launch EXIT'
assert_count 1 "trap 'cleanup_remote_launch 130' INT"
assert_count 1 "trap 'cleanup_remote_launch 143' TERM"
assert_count 1 "systemctl stop \\\"\${unit_name}.service\\\""
assert_count 1 "rm -f -- \\\"\${audit_helper_remote}\\\""
assert_count 1 '--property=RuntimeMaxSec=1min'
assert_count 1 "--unit=\"\${active_inner_unit}\""
assert_count 1 'stop_active_inner_unit() {'
assert_count 1 'if ! stop_active_inner_unit; then'
assert_count 1 "systemctl is-active --quiet \"\${unit}.service\""
assert_count 1 "restored_config=\"\${evidence_dir}/restored-config.yaml\""
assert_count 1 'install -o root -g hermes-agent -m 0640'
assert_count 2 "\"\${imported_config}\" \"\${restored_config}\""
assert_count 1 "BindReadOnlyPaths=\${config_artifact}:\${hermes_home}/config.yaml"
assert_count 1 "--property=\"ReadWritePaths=\${read_write_paths}\""
assert_count 1 "test \"\${writable_path}\" = \"\${backup_stage}\""
assert_count 1 "hermes-agent:hermes-agent:700"
if grep --fixed-strings --quiet \
  "BindReadOnlyPaths=\${managed_config}:\${hermes_home}/config.yaml" "${script_path}"; then
  printf 'Restored commands must not substitute the live managed configuration.\n' >&2
  exit 1
fi
assert_count 3 \
  "timeout --signal=TERM --kill-after=10s \"\${operation_timeout_seconds}\""
assert_count 2 'timeout --signal=TERM --kill-after=2s 15s'
assert_count 7 'timeout --kill-after=5s 30s'

primary_seconds="$(sed -n 's/^primary_deadline_seconds=//p' "${script_path}")"
outer_seconds="$(sed -n 's/^outer_runtime_seconds=//p' "${script_path}")"
operation_seconds="$(sed -n 's/^operation_timeout_seconds=//p' "${script_path}")"
# Emergency restore + export + audit + state read + five cleanup operations,
# plus a full operation-sized scheduling reserve.
worst_case_seconds=$((
  primary_seconds + operation_seconds * 3 + 15 + 30 * 5 + operation_seconds
))
if (( outer_seconds <= worst_case_seconds )); then
  printf 'Outer runtime %s does not exceed worst-case budget %s.\n' \
    "${outer_seconds}" "${worst_case_seconds}" >&2
  exit 1
fi

grep --fixed-strings --quiet \
  "<\"\${script_dir}/hermes_audit.py\"" "${script_path}"
grep --fixed-strings --quiet \
  "\"\${restore_home}\" \"\${action_source}\" \"backup-restore action\"" "${script_path}"
grep --fixed-strings --quiet \
  "\"\${restore_home}\" \"\${restore_source}\" \"backup-restore cleanup\"" "${script_path}"
grep --fixed-strings --quiet \
  "\"\${restore_home}\" \"\${action_source}\" \"\${restored_config}\"" "${script_path}"
grep --fixed-strings --quiet \
  "\"\${restore_home}\" \"\${restore_source}\" \"\${restored_config}\"" "${script_path}"
grep --fixed-strings --quiet \
  "\"\${source_home}\" \"backup\" \"\${managed_config}\"" "${script_path}"
grep --fixed-strings --quiet \
  "\"\${source_home}\" \"backup\" \"\${managed_config}\" \"\${backup_stage}\"" \
  "${script_path}"

mkdir "${test_dir}/bin"
touch "${test_dir}/config.json"

cat >"${test_dir}/bin/jq" <<'EOF'
#!/usr/bin/env bash
case $2 in
  .home_assistant_api_url)
    printf '%s\n' 'http://homeassistant.local:8123/api'
    ;;
  '.entities[0].home_assistant_entity_id')
    printf '%s\n' 'light.test'
    ;;
  '.entities[0].risk // empty')
    printf '%s\n' 'non-critical'
    ;;
esac
EOF

cat >"${test_dir}/bin/ssh" <<'EOF'
#!/usr/bin/env bash
command_text=${*: -1}
printf '%s\n' "${command_text}" >>"${SSH_TEST_LOG:?}"
if [[ "${command_text}" == *'systemd-run'* ]]; then
  exit 75
fi
EOF
chmod +x "${test_dir}/bin/jq" "${test_dir}/bin/ssh"

if PATH="${test_dir}/bin:${PATH}" SSH_TEST_LOG="${test_dir}/ssh.log" \
  PISERV_IP=192.0.2.10 "${script_path}" "${test_dir}/config.json" \
  >"${test_dir}/stdout" 2>"${test_dir}/stderr"; then
  printf 'Expected an interrupted SSH launch to fail.\n' >&2
  exit 1
fi

assert_log_count() {
  local expected=$1
  local pattern=$2
  local actual

  actual="$(grep --fixed-strings --count -- "${pattern}" "${test_dir}/ssh.log")"
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'Expected %s SSH log occurrences of %s, found %s.\n' \
      "${expected}" "${pattern}" "${actual}" >&2
    return 1
  fi
}

assert_log_count 1 'systemd-run --unit='
assert_log_count 1 'systemctl stop "hermes-home-assistant-restore-proof-'
assert_log_count 1 'systemctl reset-failed "hermes-home-assistant-restore-proof-'
assert_log_count 1 'rm -f -- "/run/hermes-home-assistant-restore-proof-'

cat >"${test_dir}/bin/ssh" <<'EOF'
#!/usr/bin/env bash
command_text=${*: -1}
printf '%s\n' "${command_text}" >>"${SSH_TEST_LOG:?}"
if [[ "${command_text}" == *'systemd-run'* ]]; then
  sleep 30
fi
EOF
chmod +x "${test_dir}/bin/ssh"
: >"${test_dir}/ssh.log"
PATH="${test_dir}/bin:${PATH}" SSH_TEST_LOG="${test_dir}/ssh.log" \
  PISERV_IP=192.0.2.10 "${script_path}" "${test_dir}/config.json" \
  >"${test_dir}/signal-stdout" 2>"${test_dir}/signal-stderr" &
signal_pid=$!
for _ in {1..50}; do
  if grep --fixed-strings --quiet 'systemd-run --unit=' "${test_dir}/ssh.log"; then
    break
  fi
  sleep 0.1
done
kill -TERM "${signal_pid}"
set +e
wait "${signal_pid}"
signal_status=$?
set -e
if (( signal_status != 143 )); then
  printf 'Expected signal cleanup status 143, got %s.\n' "${signal_status}" >&2
  exit 1
fi

cat >"${test_dir}/malformed-audit.jsonl" <<'EOF'
{"source":"fixture","messages":[{"tool_calls":[{"function":{"name":"tool_call","arguments":{"name":"mcp__home_assistant_assist__HassTurnOn","arguments":{"name":"light.test"}}}},{"function":null}]}]}
EOF
if python3 "${repo_root}/scripts/hermes_audit.py" \
  --export "${test_dir}/malformed-audit.jsonl" \
  --source fixture --entity light.test --label fixture --expected-state on \
  >/dev/null 2>&1; then
  printf 'Expected a null tool-call function record to fail closed.\n' >&2
  exit 1
fi
