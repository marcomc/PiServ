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

run_watchdog() {
    local device_status="$1"
    local runtime_seconds="$2"
    local watchdog_status

    : > "${test_log}"
    PATH="${role_root}/tests/fixtures/bin:${PATH}" \
        WIFI_WATCHDOG_TEST_LOG="${test_log}" \
        WIFI_WATCHDOG_TEST_DEVICE_STATUS="${device_status}" \
        "${rendered_script}" &
    watchdog_pid=$!

    /bin/sleep "${runtime_seconds}"
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
}

run_watchdog 'wlan0:disconnected' 2

grep -Fxq 'device disconnect wlan0' "${test_log}"
grep -Fxq 'device connect wlan0' "${test_log}"
if grep -Fq 'connection ' "${test_log}"; then
    printf 'watchdog selected a named connection despite an empty configuration\n' >&2
    exit 1
fi

run_watchdog 'wlan0:connected' 1

grep -Fxq 'ip -4 route show default dev wlan0' "${test_log}"
grep -Fxq 'ping -I wlan0 -c 1 -W 2 192.0.2.1' "${test_log}"
