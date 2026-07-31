#!/usr/bin/env bash
set -euo pipefail

CDPATH=''
role_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
rendered_script="${test_dir}/wifi-connectivity-watchdog"
test_log="${test_dir}/calls.log"
invalid_service_path_output="${test_dir}/invalid-service-path.log"
monotonic_clock_file="${test_dir}/uptime"
watchdog_pid=""
monotonic_clock_writer_pid=""

cleanup() {
    if [[ -n "${watchdog_pid}" ]] && kill -0 "${watchdog_pid}" 2>/dev/null; then
        kill -TERM "${watchdog_pid}" 2>/dev/null || true
        wait "${watchdog_pid}" 2>/dev/null || true
    fi
    if [[ -n "${monotonic_clock_writer_pid}" ]] && kill -0 "${monotonic_clock_writer_pid}" 2>/dev/null; then
        kill -TERM "${monotonic_clock_writer_pid}" 2>/dev/null || true
        wait "${monotonic_clock_writer_pid}" 2>/dev/null || true
    fi
    rm -rf "${test_dir}"
}
trap cleanup EXIT

if ansible-playbook "${role_root}/tests/test-invalid-service-path.yml" \
    > "${invalid_service_path_output}" 2>&1; then
    printf 'invalid service-path configuration unexpectedly passed\n' >&2
    exit 1
fi

grep -Fq 'service path filename must equal the service name' "${invalid_service_path_output}"

if ansible-playbook "${role_root}/tests/test-invalid-service-directory.yml" \
    > "${invalid_service_path_output}" 2>&1; then
    printf 'invalid service-directory configuration unexpectedly passed\n' >&2
    exit 1
fi

grep -Fq '/etc/systemd/system' "${invalid_service_path_output}"

if ansible-playbook "${role_root}/tests/test-invalid-script-directory.yml" \
    > "${invalid_service_path_output}" 2>&1; then
    printf 'invalid script-directory configuration unexpectedly passed\n' >&2
    exit 1
fi

grep -Fq '/usr/local/sbin' "${invalid_service_path_output}"

ansible localhost -c local -m ansible.builtin.template \
    -a "src=${role_root}/templates/wifi-connectivity-watchdog.sh.j2 dest=${rendered_script} mode=0750" \
    -e 'wifi_watchdog_interface=wlan0 wifi_watchdog_connection=""' \
    -e 'wifi_watchdog_gateway_probe="" wifi_watchdog_dns_probe=example.com' \
    -e 'wifi_watchdog_check_interval_seconds=1' \
    -e 'wifi_watchdog_connection_recovery_after_seconds=1' \
    -e 'wifi_watchdog_networkmanager_recovery_after_seconds=10' \
    -e 'wifi_watchdog_reboot_after_seconds=0' \
    -e 'wifi_watchdog_networkmanager_service_name=NetworkManager.service' \
    -e "wifi_watchdog_monotonic_clock_path=${monotonic_clock_file}" >/dev/null

grep -Fq "monotonic_clock_path=${monotonic_clock_file}" "${rendered_script}"
if grep -Fq 'SECONDS' "${rendered_script}"; then
    printf 'watchdog used Bash SECONDS instead of the kernel monotonic clock\n' >&2
    exit 1
fi

write_monotonic_clock() {
    local seconds=0

    while :; do
        printf '%s.00 0.00\n' "${seconds}" > "${monotonic_clock_file}"
        seconds=$((seconds + 1))
        /bin/sleep 1
    done
}

printf '%s\n' '0.00 0.00' > "${monotonic_clock_file}"
write_monotonic_clock &
monotonic_clock_writer_pid=$!

run_watchdog() {
    local device_status="$1"
    local runtime_seconds="$2"
    local getent_failure="${3:-0}"
    local watchdog_status

    : > "${test_log}"
    LC_ALL=POSIX \
        PATH="${role_root}/tests/fixtures/bin:${PATH}" \
        WIFI_WATCHDOG_TEST_LOG="${test_log}" \
        WIFI_WATCHDOG_TEST_DEVICE_STATUS="${device_status}" \
        WIFI_WATCHDOG_TEST_GETENT_FAILURE="${getent_failure}" \
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

grep -Fxq 'device status locale=C' "${test_log}"
grep -Fxq 'device disconnect wlan0' "${test_log}"
grep -Fxq 'device connect wlan0' "${test_log}"
if grep -Fq 'connection ' "${test_log}"; then
    printf 'watchdog selected a named connection despite an empty configuration\n' >&2
    exit 1
fi
if grep -Fq 'date ' "${test_log}"; then
    printf 'watchdog used the wall clock for its offline timer\n' >&2
    exit 1
fi

run_watchdog 'wlan0:connected' 1

grep -Fxq 'ip -4 route show default dev wlan0' "${test_log}"
grep -Fxq 'ping -I wlan0 -c 1 -W 2 192.0.2.1' "${test_log}"
grep -Fxq 'getent ahostsv4 example.com' "${test_log}"
grep -Fxq 'ping -I wlan0 -c 1 -W 2 203.0.113.1' "${test_log}"

run_watchdog 'wlan0:connected' 2 1

grep -Fxq 'getent ahostsv4 example.com' "${test_log}"
grep -Fxq 'device disconnect wlan0' "${test_log}"
grep -Fxq 'device connect wlan0' "${test_log}"
if grep -Fq 'ping -I wlan0 -c 1 -W 2 203.0.113.1' "${test_log}"; then
    printf 'watchdog pinged a DNS address after its lookup failed\n' >&2
    exit 1
fi
