#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
script_path="${repo_root}/scripts/verify-hermes-home-assistant-backup-restore.sh"

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

grep --fixed-strings --quiet \
  "<\"\${script_dir}/hermes_audit.py\"" "${script_path}"
grep --fixed-strings --quiet \
  "\"\${restore_home}\" \"\${action_source}\" \"backup-restore action\"" "${script_path}"
grep --fixed-strings --quiet \
  "\"\${restore_home}\" \"\${restore_source}\" \"backup-restore cleanup\"" "${script_path}"
