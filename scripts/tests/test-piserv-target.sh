#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/piserv-target.sh
source "${repo_root}/scripts/lib/piserv-target.sh"

assert_target() {
  local address=$1
  local expected=$2
  local actual

  actual="$(PISERV_IP="${address}" PISERV_USER=operator piserv_ssh_target)"
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'Expected target %s, got %s\n' "${expected}" "${actual}" >&2
    return 1
  fi
}

assert_rejected() {
  local address=$1
  local status

  set +e
  PISERV_IP="${address}" piserv_ssh_target >/dev/null 2>&1
  status=$?
  set -e
  if [[ "${status}" -eq 0 ]]; then
    printf 'Expected PISERV_IP to be rejected: %q\n' "${address}" >&2
    return 1
  fi
}

assert_target 192.0.2.10 operator@192.0.2.10
assert_target 2001:db8::10 'operator@[2001:db8::10]'

assert_rejected ''
assert_rejected piserv.example.com
assert_rejected operator@192.0.2.10
assert_rejected ' 192.0.2.10'
assert_rejected '192.0.2.10 '
assert_rejected 192.0.2.10/24
assert_rejected -oProxyCommand=fixture

runbook="${repo_root}/docs/runbooks/hermes-home-apple-home.md"
grep -Fq "source \"\${repo_root}/scripts/lib/piserv-target.sh\"" "${runbook}"
grep -Fq "piserv_target=\"\$(piserv_ssh_target)\"" "${runbook}"
if grep -Fq "admin@\${PISERV_IP:-PiServ.local}" "${runbook}"; then
  printf 'Runbook must not reconstruct the PiServ SSH target directly.\n' >&2
  exit 1
fi
