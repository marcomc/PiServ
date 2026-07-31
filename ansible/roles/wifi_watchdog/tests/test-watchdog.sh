#!/usr/bin/env bash
set -euo pipefail

CDPATH=''
role_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
rendered_script="${test_dir}/wifi-connectivity-watchdog"
test_log="${test_dir}/calls.log"
watchdog_pid=""

cleanup() {
    if [[ -n "${watchdog_pid}" ]] && kill -0 "${watchdog_pid}" 2>/dev/null; then
        kill -TERM "${watchdog_pid}" 2>/dev/null || true
        wait "${watchdog_pid}" 2>/dev/null || true
    fi
    rm -rf "${test_dir}"
}
trap cleanup EXIT

ansible localhost -c local -m ansible.builtin.template \
    -a "src=${role_root}/templates/wifi-connectivity-watchdog.sh.j2 dest=${rendered_script} mode=0750" \
    -e 'wifi_watchdog_interface=wlan0 wifi_watchdog_connection=""' \
    -e 'wifi_watchdog_gateway_probe="" wifi_watchdog_dns_probe=""' \
    -e 'wifi_watchdog_check_interval_seconds=1' \
    -e 'wifi_watchdog_connection_recovery_after_seconds=1' \
    -e 'wifi_watchdog_networkmanager_recovery_after_seconds=10' \
    -e 'wifi_watchdog_reboot_after_seconds=0' \
    -e 'wifi_watchdog_networkmanager_service_name=NetworkManager.service' >/dev/null

PATH="${role_root}/tests/fixtures/bin:${PATH}" \
    WIFI_WATCHDOG_TEST_LOG="${test_log}" \
    "${rendered_script}" &
watchdog_pid=$!

/bin/sleep 2
kill -TERM "${watchdog_pid}"
set +e
wait "${watchdog_pid}" 2>/dev/null
watchdog_status=$?
set -e
watchdog_pid=""

if [[ "${watchdog_status}" -ne 143 ]]; then
    printf 'unexpected watchdog exit status: %s\n' "${watchdog_status}" >&2
    exit 1
fi

grep -Fxq 'device disconnect wlan0' "${test_log}"
grep -Fxq 'device connect wlan0' "${test_log}"
if grep -Fq 'connection ' "${test_log}"; then
    printf 'watchdog selected a named connection despite an empty configuration\n' >&2
    exit 1
fi
