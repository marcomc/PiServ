#!/usr/bin/env bash
set -euo pipefail

if [[ "${0##*/}" == cp ]]; then
  : "${SNAPSHOT_MARKER:=}"
  : "${SNAPSHOT_MODE:=stable}"
  : "${SNAPSHOT_PAYLOAD:=}"
  : "${SNAPSHOT_SOURCE:=}"
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
    if [[ "${SNAPSHOT_MODE}" == fail ]]; then
      printf 'injected source snapshot failure\n' >&2
      exit 74
    fi
    /usr/bin/cp "$@"
    case "${SNAPSHOT_MODE}" in
      replace-once)
        if [[ ! -e "${SNAPSHOT_MARKER}" ]]; then
          /usr/bin/mv "${SNAPSHOT_PAYLOAD}" "${SNAPSHOT_SOURCE}"
          /usr/bin/touch "${SNAPSHOT_MARKER}"
        fi
        ;;
      in-place-once)
        if [[ ! -e "${SNAPSHOT_MARKER}" ]]; then
          /usr/bin/fdtput --type s "${SNAPSHOT_SOURCE}" /chosen bootargs \
            "${SNAPSHOT_PAYLOAD}"
          /usr/bin/touch "${SNAPSHOT_MARKER}"
        fi
        ;;
      unstable)
        count=0
        [[ ! -f "${SNAPSHOT_MARKER}" ]] || count="$(<"${SNAPSHOT_MARKER}")"
        ((count += 1))
        printf '%s\n' "${count}" >"${SNAPSHOT_MARKER}"
        /usr/bin/fdtput --type s "${SNAPSHOT_SOURCE}" /chosen bootargs \
          "reboot=w cgroup_disable=memory quiet snapshot-unstable-${count}"
        ;;
      stable)
        ;;
      *)
        printf 'unknown source snapshot mode: %s\n' "${SNAPSHOT_MODE}" >&2
        exit 2
        ;;
    esac
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
readonly snapshot_marker="${vendor_dtb}.snapshot-marker"
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

artifact_checksums() {
  /usr/bin/sha256sum "${config_path}" "${managed_dtb}" "${source_state_path}"
}

source_state_checksum() {
  /usr/bin/sha256sum "${source_state_path}" | /usr/bin/awk '{print $1}'
}

restore_baseline() {
  set_bootargs "${vendor_dtb}" 'reboot=w cgroup_disable=memory quiet'
  "${helper}" --apply >/dev/null
}

run_retry() {
  local mode=$1
  local change_mode=$2
  local old_bootargs=$3
  local new_bootargs=$4
  local expected_status=$5
  local expected_managed_bootargs=$6
  local actual_bootargs
  local identity_after
  local identity_before
  local new_sha
  local output
  local payload="${new_bootargs}"
  local state_after
  local state_before

  set_bootargs "${vendor_dtb}" "${old_bootargs}"
  if [[ "${change_mode}" == replace-once ]]; then
    /usr/bin/cp "${vendor_dtb}" "${replacement_dtb}"
    set_bootargs "${replacement_dtb}" "${new_bootargs}"
    payload="${replacement_dtb}"
  fi
  rm -f -- "${snapshot_marker}"
  identity_before="$(/usr/bin/stat -c '%d:%i' "${vendor_dtb}")"
  state_before="$(source_state_checksum)"
  output="$(PATH="${fake_bin}:${PATH}" \
    SNAPSHOT_MARKER="${snapshot_marker}" \
    SNAPSHOT_MODE="${change_mode}" \
    SNAPSHOT_PAYLOAD="${payload}" \
    SNAPSHOT_SOURCE="${vendor_dtb}" \
    "${helper}" "${mode}")"

  new_sha="$(/usr/bin/sha256sum "${vendor_dtb}" | /usr/bin/awk '{print $1}')"
  require_contains "${output}" "status=${expected_status}"
  require_contains "${output}" "source_dtb_sha256=${new_sha}"
  actual_bootargs="$(/usr/bin/fdtget --type s "${vendor_dtb}" /chosen bootargs)"
  [[ "${actual_bootargs}" == "${new_bootargs}" ]] || \
    fail 'live vendor generation was not changed'
  if [[ "${change_mode}" == in-place-once ]]; then
    identity_after="$(/usr/bin/stat -c '%d:%i' "${vendor_dtb}")"
    [[ "${identity_after}" == "${identity_before}" ]] || \
      fail 'in-place mutation replaced the vendor inode'
  fi

  if [[ "${mode}" == --check ]]; then
    state_after="$(source_state_checksum)"
    [[ "${state_after}" == "${state_before}" ]] || \
      fail 'check mode changed source state'
  elif [[ -z "${expected_managed_bootargs}" ]]; then
    [[ ! -e "${managed_dtb}" ]] || fail 'vendor-enabled apply retained managed DTB'
    require_contains "$(<"${source_state_path}")" "source_dtb_sha256=${new_sha}"
  else
    actual_bootargs="$(/usr/bin/fdtget --type s \
      "${managed_dtb}" /chosen bootargs)"
    [[ "${actual_bootargs}" == "${expected_managed_bootargs}" ]] || \
      fail 'managed DTB mixed source generations'
    require_contains "$(<"${source_state_path}")" "source_dtb_sha256=${new_sha}"
  fi
  restore_baseline
}

run_failure_case() {
  local failure_mode=$1
  local expected_error=$2
  local after_failure
  local before_failure
  local failure_output
  local failure_status
  local state_after_fallback
  local state_before_fallback

  restore_baseline
  rm -f -- "${snapshot_marker}"
  before_failure="$(artifact_checksums)"
  set +e
  failure_output="$(PATH="${fake_bin}:${PATH}" \
    SNAPSHOT_MARKER="${snapshot_marker}" \
    SNAPSHOT_MODE="${failure_mode}" \
    SNAPSHOT_SOURCE="${vendor_dtb}" \
    "${helper}" --apply 2>&1)"
  failure_status=$?
  set -e
  ((failure_status != 0)) || fail "${failure_mode} direct apply unexpectedly succeeded"
  require_contains "${failure_output}" "${expected_error}"
  after_failure="$(artifact_checksums)"
  [[ "${after_failure}" == "${before_failure}" ]] || \
    fail "${failure_mode} direct apply changed managed state"

  restore_baseline
  rm -f -- "${snapshot_marker}"
  state_before_fallback="$(source_state_checksum)"
  set +e
  failure_output="$(PATH="${fake_bin}:${PATH}" \
    SNAPSHOT_MARKER="${snapshot_marker}" \
    SNAPSHOT_MODE="${failure_mode}" \
    SNAPSHOT_SOURCE="${vendor_dtb}" \
    "${helper}" --refresh 2>&1)"
  failure_status=$?
  set -e
  ((failure_status != 0)) || fail "${failure_mode} refresh unexpectedly succeeded"
  require_contains "${failure_output}" "${expected_error}"
  require_contains "${failure_output}" 'was disabled after regeneration failed'
  [[ ! -e "${managed_dtb}" ]] || fail "${failure_mode} fallback retained managed DTB"
  state_after_fallback="$(source_state_checksum)"
  [[ "${state_after_fallback}" == "${state_before_fallback}" ]] || \
    fail "${failure_mode} fallback changed source state"
  restore_baseline
}

mkdir -p "${fake_bin}"
script_path="$(readlink -f "$0")"
readonly script_path
ln -sf "${script_path}" "${fake_bin}/cp"
trap 'rm -rf -- "${fake_bin}" "${replacement_dtb}" "${snapshot_marker}"' EXIT

run_retry --check replace-once \
  'reboot=w cgroup_disable=memory quiet snapshot-check-old' \
  'reboot=w cgroup_disable=memory quiet snapshot-check-new' \
  managed-dtb-required ''
run_retry --apply replace-once \
  'reboot=w cgroup_disable=memory quiet snapshot-apply-old' \
  'reboot=w cgroup_disable=memory quiet snapshot-apply-new' \
  managed-dtb-required 'reboot=w quiet snapshot-apply-new'
run_retry --apply replace-once \
  'reboot=w cgroup_disable=memory quiet snapshot-vendor-old' \
  'reboot=w quiet snapshot-vendor-new' \
  disabled ''
run_retry --apply in-place-once \
  'reboot=w cgroup_disable=memory quiet snapshot-in-place-old' \
  'reboot=w cgroup_disable=memory quiet snapshot-in-place-new' \
  managed-dtb-required 'reboot=w quiet snapshot-in-place-new'

run_failure_case fail 'injected source snapshot failure'
run_failure_case unstable \
  'vendor Device Tree changed during snapshot capture after 3 attempts'
