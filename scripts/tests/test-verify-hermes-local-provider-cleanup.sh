#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source_script="${repo_root}/scripts/verify-hermes-local-provider.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT

extract_cleanup() {
  awk '
    /^cleanup\(\) \{/ { capture = 1 }
    capture { print }
    capture && /^\}/ { exit }
  ' "${source_script}"
}

run_case() {
  local started=$1
  local log_file="${work_dir}/${started}.log"
  local harness="${work_dir}/${started}.sh"

  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf 'service_name=%q\n' hermes-local-model-fixture.service
    printf 'service_started_by_invocation=%q\n' "${started}"
    printf 'work_dir=%q\n' "${work_dir}/remote-${started}"
    printf '%s\n' 'remove_limit_as_override() { :; }'
    printf '%s\n' "systemctl() { printf '%s\\n' \"\$*\" >> \"\${MOCK_SYSTEMCTL_LOG}\"; }"
    extract_cleanup
    printf '%s\n' "mkdir -p -- \"\${work_dir}\"" 'cleanup'
  } >"${harness}"
  chmod 0700 "${harness}"
  MOCK_SYSTEMCTL_LOG="${log_file}" "${harness}"

  if [[ "${started}" == true ]]; then
    grep -Fx 'stop hermes-local-model-fixture.service' "${log_file}" >/dev/null
  elif [[ -e "${log_file}" ]]; then
    printf 'Cleanup stopped a service it did not start.\n' >&2
    return 1
  fi
}

run_case false
run_case true
