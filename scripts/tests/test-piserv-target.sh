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

assert_user_rejected() {
  local user=$1
  local status

  set +e
  PISERV_IP=192.0.2.10 PISERV_USER="${user}" piserv_ssh_target >/dev/null 2>&1
  status=$?
  set -e
  if [[ "${status}" -eq 0 ]]; then
    printf 'Expected PISERV_USER to be rejected: %q\n' "${user}" >&2
    return 1
  fi
}

assert_target 192.0.2.10 operator@192.0.2.10
assert_target 2001:db8::10 operator@2001:db8::10
target="$(unset PISERV_IP; PISERV_USER=operator piserv_ssh_target)"
[[ "${target}" == operator@PiServ.local ]]

literal="$(PISERV_IP=192.0.2.10 piserv_ip_literal)"
[[ "${literal}" == 192.0.2.10 ]]
literal="$(PISERV_IP=2001:db8::10 piserv_ip_literal)"
[[ "${literal}" == 2001:db8::10 ]]
target="$(PISERV_USER=operator piserv_ssh_target_from_ip 192.0.2.10)"
[[ "${target}" == operator@192.0.2.10 ]]
target="$(PISERV_USER=operator piserv_ssh_target_from_ip 2001:db8::10)"
[[ "${target}" == operator@2001:db8::10 ]]

assert_rejected ''
assert_rejected piserv.example.com
assert_rejected operator@192.0.2.10
assert_rejected ' 192.0.2.10'
assert_rejected '192.0.2.10 '
assert_rejected 192.0.2.10/24
assert_rejected -oProxyCommand=fixture
assert_user_rejected -oProxyCommand=fixture
assert_user_rejected 'bad user'

runbook="${repo_root}/docs/runbooks/hermes-home-apple-home.md"
grep -Fq "source \"\${repo_root}/scripts/lib/piserv-target.sh\"" "${runbook}"
grep -Fq "piserv_target=\"\$(piserv_ssh_target)\"" "${runbook}"
if grep -Fq "admin@\${PISERV_IP:-PiServ.local}" "${runbook}"; then
  printf 'Runbook must not reconstruct the PiServ SSH target directly.\n' >&2
  exit 1
fi

runbook="${repo_root}/docs/runbooks/homeassistant-cli.md"
grep -Fq "source \"\${repo_root}/scripts/lib/piserv-target.sh\"" "${runbook}"
grep -Fq "piserv_ip=\"\$(piserv_ip_literal)\"" "${runbook}"
grep -Fq "piserv_target=\"\$(piserv_ssh_target_from_ip \"\${piserv_ip}\")\"" "${runbook}"
grep -Fq "ssh \"\${piserv_target}\"" "${runbook}"
grep -Fq -- "-e \"ansible_host=\${piserv_ip}\"" "${runbook}"
if grep -Fq "admin@\${PISERV_IP}" "${runbook}"; then
  printf 'Runbook must use the shared validated PiServ target helper.\n' >&2
  exit 1
fi
