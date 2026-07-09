#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_command ansible
require_command git
require_command shellcheck

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "${REPO_ROOT}"

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/piserv-shellcheck.XXXXXX")
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

file_list="${tmpdir}/git-files"
git ls-files -z -co --exclude-standard > "${file_list}"

shell_files=()
while IFS= read -r -d '' tracked_path; do
  [[ -f "${tracked_path}" ]] || continue
  [[ "${tracked_path}" != *.j2 ]] || continue
  first_line=""
  IFS= read -r first_line < "${tracked_path}" || true
  case "${first_line}" in
    '#!'*sh*)
      shell_files+=("${tracked_path}")
      ;;
    *)
      ;;
  esac
done < "${file_list}"

if [[ "${#shell_files[@]}" -gt 0 ]]; then
  shellcheck --enable=all "${shell_files[@]}"
fi

ansible localhost, \
  -c local \
  -m ansible.builtin.template \
  -a "src=ansible/roles/msmtp/templates/msmtp-system.sh.j2 dest=${tmpdir}/msmtp-system.sh" \
  -e '{"msmtp_config_path":"/etc/msmtprc","msmtp_binary_path":"/usr/bin/msmtp"}' \
  >/dev/null

shellcheck --enable=all -s sh "${tmpdir}/msmtp-system.sh"
