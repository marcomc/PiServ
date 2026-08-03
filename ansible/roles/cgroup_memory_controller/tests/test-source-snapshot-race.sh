#!/usr/bin/env bash
set -euo pipefail

if [[ "${0##*/}" == cp ]]; then
  : "${SNAPSHOT_SOURCE:=}"
  : "${SNAPSHOT_REPLACEMENT:=}"
  : "${SNAPSHOT_FAIL:=false}"
  source_path=''
  destination=''
  for argument in "$@"; do
    [[ "${argument}" == -* ]] && continue
    if [[ -z "${source_path}" ]]; then
      source_path="${argument}"
    else
      destination="${argument}"
    fi
  done
  if [[ "${source_path}" == "${SNAPSHOT_SOURCE}" && \
    "${destination}" == */source.dtb ]]; then
    if [[ "${SNAPSHOT_FAIL}" == true ]]; then
      printf 'injected source snapshot failure\n' >&2
      exit 74
    fi
    /usr/bin/cp "$@"
    /usr/bin/mv "${SNAPSHOT_REPLACEMENT}" "${SNAPSHOT_SOURCE}"
    exit 0
  fi
  exec /usr/bin/cp "$@"
fi

[[ $# -eq 5 ]] || {
  printf 'Usage: %s HELPER VENDOR_DTB MANAGED_DTB CONFIG SOURCE_STATE\n' "$0" >&2
  exit 2
}

readonly helper=$1
readonly vendor_dtb=$2
readonly managed_dtb=$3
readonly config_path=$4
readonly source_state_path=$5
readonly replacement_dtb="${vendor_dtb}.replacement"
fake_bin="$(dirname "${vendor_dtb}")/snapshot-bin"
readonly fake_bin

fail() {
  printf 'source snapshot test: %s\n' "$*" >&2
  exit 1
}

require_contains() {
  local content=$1
  local expected=$2

  [[ "${content}" == *"${expected}"* ]] || fail "missing expected output: ${expected}"
}

set_bootargs() {
  /usr/bin/fdtput --type s "$1" /chosen bootargs "$2"
}

restore_baseline() {
  set_bootargs "${vendor_dtb}" 'reboot=w cgroup_disable=memory quiet'
  "${helper}" --apply >/dev/null
}

run_race() {
  local mode=$1
  local old_bootargs=$2
  local new_bootargs=$3
  local expected_status=$4
  local expected_managed_bootargs=$5
  local actual_bootargs
  local old_sha
  local output
  local state_after
  local state_before

  set_bootargs "${vendor_dtb}" "${old_bootargs}"
  /usr/bin/cp "${vendor_dtb}" "${replacement_dtb}"
  set_bootargs "${replacement_dtb}" "${new_bootargs}"
  old_sha="$(/usr/bin/sha256sum "${vendor_dtb}" | /usr/bin/awk '{print $1}')"
  state_before="$(/usr/bin/sha256sum "${source_state_path}" | /usr/bin/awk '{print $1}')"
  output="$(PATH="${fake_bin}:${PATH}" \
    SNAPSHOT_SOURCE="${vendor_dtb}" \
    SNAPSHOT_REPLACEMENT="${replacement_dtb}" \
    "${helper}" "${mode}")"

  require_contains "${output}" "status=${expected_status}"
  require_contains "${output}" "source_dtb_sha256=${old_sha}"
  actual_bootargs="$(/usr/bin/fdtget --type s "${vendor_dtb}" /chosen bootargs)"
  [[ "${actual_bootargs}" == "${new_bootargs}" ]] || \
    fail 'live vendor generation was not replaced'

  if [[ "${mode}" == --check ]]; then
    state_after="$(/usr/bin/sha256sum \
      "${source_state_path}" | /usr/bin/awk '{print $1}')"
    [[ "${state_after}" == "${state_before}" ]] || \
      fail 'check mode changed source state'
  elif [[ -z "${expected_managed_bootargs}" ]]; then
    [[ ! -e "${managed_dtb}" ]] || fail 'vendor-enabled apply retained managed DTB'
    require_contains "$(<"${source_state_path}")" "source_dtb_sha256=${old_sha}"
  else
    actual_bootargs="$(/usr/bin/fdtget --type s \
      "${managed_dtb}" /chosen bootargs)"
    [[ "${actual_bootargs}" == "${expected_managed_bootargs}" ]] || \
      fail 'managed DTB mixed generations'
    require_contains "$(<"${source_state_path}")" "source_dtb_sha256=${old_sha}"
  fi
  restore_baseline
}

mkdir -p "${fake_bin}"
script_path="$(readlink -f "$0")"
readonly script_path
ln -sf "${script_path}" "${fake_bin}/cp"
trap 'rm -rf -- "${fake_bin}" "${replacement_dtb}"' EXIT

run_race --check \
  'reboot=w cgroup_disable=memory quiet snapshot-check-old' \
  'reboot=w cgroup_disable=memory quiet snapshot-check-new' \
  managed-dtb-required ''
run_race --apply \
  'reboot=w cgroup_disable=memory quiet snapshot-apply-old' \
  'reboot=w cgroup_disable=memory quiet snapshot-apply-new' \
  managed-dtb-required 'reboot=w quiet snapshot-apply-old'
run_race --apply \
  'reboot=w quiet snapshot-vendor-old' \
  'reboot=w cgroup_disable=memory quiet snapshot-vendor-new' \
  disabled ''

before_failure="$(/usr/bin/sha256sum \
  "${config_path}" "${managed_dtb}" "${source_state_path}")"
set +e
failure_output="$(PATH="${fake_bin}:${PATH}" SNAPSHOT_FAIL=true \
  SNAPSHOT_SOURCE="${vendor_dtb}" "${helper}" --apply 2>&1)"
failure_status=$?
set -e
(( failure_status != 0 )) || fail 'snapshot failure unexpectedly succeeded'
require_contains "${failure_output}" 'injected source snapshot failure'
after_failure="$(/usr/bin/sha256sum \
  "${config_path}" "${managed_dtb}" "${source_state_path}")"
[[ "${after_failure}" == "${before_failure}" ]] || \
  fail 'snapshot failure changed managed state'

state_before_fallback="$(/usr/bin/sha256sum \
  "${source_state_path}" | /usr/bin/awk '{print $1}')"
set +e
failure_output="$(PATH="${fake_bin}:${PATH}" SNAPSHOT_FAIL=true \
  SNAPSHOT_SOURCE="${vendor_dtb}" "${helper}" --refresh 2>&1)"
failure_status=$?
set -e
(( failure_status != 0 )) || fail 'refresh snapshot failure unexpectedly succeeded'
require_contains "${failure_output}" 'injected source snapshot failure'
require_contains "${failure_output}" 'was disabled after regeneration failed'
[[ ! -e "${managed_dtb}" ]] || fail 'refresh fallback retained managed DTB'
state_after_fallback="$(/usr/bin/sha256sum \
  "${source_state_path}" | /usr/bin/awk '{print $1}')"
[[ "${state_after_fallback}" == "${state_before_fallback}" ]] || \
  fail 'refresh fallback changed source state'
restore_baseline
