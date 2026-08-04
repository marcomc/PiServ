#!/usr/bin/env bash
set -euo pipefail

CDPATH=''
role_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
rendered_script="${test_dir}/wifi-connectivity-watchdog"
named_connection_script="${test_dir}/wifi-connectivity-watchdog-named"
recovery_retry_script="${test_dir}/wifi-connectivity-watchdog-recovery-retry"
escalation_retry_script="${test_dir}/wifi-connectivity-watchdog-escalation-retry"
reboot_guard_script="${test_dir}/wifi-connectivity-watchdog-reboot-guard"
test_log="${test_dir}/calls.log"
invalid_service_path_output="${test_dir}/invalid-service-path.log"
invalid_recovery_range_output="${test_dir}/invalid-recovery-range.log"
invalid_reboot_mode_output="${test_dir}/invalid-reboot-mode.log"
invalid_internet_probe_output="${test_dir}/invalid-internet-probe.log"
monotonic_clock_file="${test_dir}/uptime"
reboot_mode_file="${test_dir}/reboot-mode"
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

if ansible-playbook "${role_root}/tests/test-invalid-recovery-range.yml" \
    > "${invalid_recovery_range_output}" 2>&1; then
    printf 'out-of-range recovery configuration unexpectedly passed\n' >&2
    exit 1
fi

grep -Fq '2147483647' "${invalid_recovery_range_output}"

if ansible-playbook "${role_root}/tests/test-invalid-reboot-mode.yml" \
    > "${invalid_reboot_mode_output}" 2>&1; then
    printf 'incomplete reboot-mode configuration unexpectedly passed\n' >&2
    exit 1
fi

grep -Fq 'reboot-mode inputs must be supplied together' "${invalid_reboot_mode_output}"

if ansible-playbook "${role_root}/tests/test-invalid-internet-probe.yml" \
    > "${invalid_internet_probe_output}" 2>&1; then
    printf 'invalid internet probe configuration unexpectedly passed\n' >&2
    exit 1
fi

grep -Fq 'Internet probes must be IPv4 literals' "${invalid_internet_probe_output}"

ansible localhost -c local -m ansible.builtin.template \
    -a "src=${role_root}/templates/wifi-connectivity-watchdog.sh.j2 dest=${rendered_script} mode=0750" \
    -e 'wifi_watchdog_interface=wlan0 wifi_watchdog_connection=""' \
    -e 'wifi_watchdog_gateway_probe="" wifi_watchdog_dns_probe=example.com' \
    -e 'wifi_watchdog_check_interval_seconds=1' \
    -e 'wifi_watchdog_connection_recovery_after_seconds=1' \
    -e 'wifi_watchdog_networkmanager_recovery_after_seconds=10' \
    -e 'wifi_watchdog_reboot_after_seconds=0' \
    -e '{"wifi_watchdog_internet_probe_addresses": ["1.1.1.1", "8.8.8.8"]}' \
    -e 'wifi_watchdog_networkmanager_service_name=NetworkManager.service' \
    -e "wifi_watchdog_monotonic_clock_path=${monotonic_clock_file}" \
    -e 'wifi_watchdog_reboot_mode_path="" wifi_watchdog_required_reboot_mode=""' >/dev/null

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
    local watchdog_script="$1"
    local device_status="$2"
    local runtime_seconds="$3"
    local getent_failure="${4:-0}"
    local active_connection="${5:-}"
    local device_connect_failure="${6:-0}"
    local networkmanager_restart_failure="${7:-0}"
    local internet_probe_failure="${8:-0}"
    local watchdog_status

    : > "${test_log}"
    LC_ALL=POSIX \
        PATH="${role_root}/tests/fixtures/bin:${PATH}" \
        WIFI_WATCHDOG_TEST_LOG="${test_log}" \
        WIFI_WATCHDOG_TEST_DEVICE_STATUS="${device_status}" \
        WIFI_WATCHDOG_TEST_GETENT_FAILURE="${getent_failure}" \
        WIFI_WATCHDOG_TEST_ACTIVE_CONNECTION="${active_connection}" \
        WIFI_WATCHDOG_TEST_DEVICE_CONNECT_FAILURE="${device_connect_failure}" \
        WIFI_WATCHDOG_TEST_NETWORKMANAGER_RESTART_FAILURE="${networkmanager_restart_failure}" \
        WIFI_WATCHDOG_TEST_INTERNET_PROBE_FAILURE="${internet_probe_failure}" \
        "${watchdog_script}" &
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

run_watchdog "${rendered_script}" 'wlan0:disconnected' 2

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

run_watchdog "${rendered_script}" $'p2p-dev-wlan0:connected\nwlan0:disconnected' 2

grep -Fxq 'device disconnect wlan0' "${test_log}"
grep -Fxq 'device connect wlan0' "${test_log}"

run_watchdog "${rendered_script}" 'wlan0:connected' 1

grep -Fxq 'ip -4 route show default dev wlan0' "${test_log}"
grep -Fxq 'ping -I wlan0 -c 1 -W 2 192.0.2.1' "${test_log}"
grep -Fxq 'getent ahostsv4 example.com' "${test_log}"
grep -Fxq 'ping -I wlan0 -c 1 -W 2 203.0.113.1' "${test_log}"

run_watchdog "${rendered_script}" 'wlan0:connected' 2 1

grep -Fxq 'getent ahostsv4 example.com' "${test_log}"
grep -Fxq 'device disconnect wlan0' "${test_log}"
grep -Fxq 'device connect wlan0' "${test_log}"
if grep -Fq 'ping -I wlan0 -c 1 -W 2 203.0.113.1' "${test_log}"; then
    printf 'watchdog pinged a DNS address after its lookup failed\n' >&2
    exit 1
fi

ansible localhost -c local -m ansible.builtin.template \
    -a "src=${role_root}/templates/wifi-connectivity-watchdog.sh.j2 dest=${named_connection_script} mode=0750" \
    -e 'wifi_watchdog_interface=wlan0 wifi_watchdog_connection=office:5g' \
    -e 'wifi_watchdog_gateway_probe="" wifi_watchdog_dns_probe=example.com' \
    -e 'wifi_watchdog_check_interval_seconds=1' \
    -e 'wifi_watchdog_connection_recovery_after_seconds=1' \
    -e 'wifi_watchdog_networkmanager_recovery_after_seconds=10' \
    -e 'wifi_watchdog_reboot_after_seconds=0' \
    -e '{"wifi_watchdog_internet_probe_addresses": ["1.1.1.1", "8.8.8.8"]}' \
    -e 'wifi_watchdog_networkmanager_service_name=NetworkManager.service' \
    -e "wifi_watchdog_monotonic_clock_path=${monotonic_clock_file}" \
    -e 'wifi_watchdog_reboot_mode_path="" wifi_watchdog_required_reboot_mode=""' >/dev/null

run_watchdog "${named_connection_script}" 'wlan0:connected' 2 0 'fallback-wifi'

grep -Fxq 'active connection locale=C' "${test_log}"
grep -Fxq 'device disconnect wlan0' "${test_log}"
grep -Fxq 'connection up office:5g ifname wlan0' "${test_log}"
if grep -Fq 'connection down office:5g' "${test_log}"; then
    printf 'named connection recovery deactivated the profile without an interface scope\n' >&2
    exit 1
fi

run_watchdog "${rendered_script}" 'wlan0:disconnected' 4 0 '' 1

connection_retries=$(grep -Fxc 'device connect wlan0' "${test_log}" || true)
if (( connection_retries < 2 )); then
    printf 'watchdog did not retry a failed connection recovery\n' >&2
    exit 1
fi

ansible localhost -c local -m ansible.builtin.template \
    -a "src=${role_root}/templates/wifi-connectivity-watchdog.sh.j2 dest=${recovery_retry_script} mode=0750" \
    -e 'wifi_watchdog_interface=wlan0 wifi_watchdog_connection=""' \
    -e 'wifi_watchdog_gateway_probe="" wifi_watchdog_dns_probe=example.com' \
    -e 'wifi_watchdog_check_interval_seconds=1' \
    -e 'wifi_watchdog_connection_recovery_after_seconds=1' \
    -e 'wifi_watchdog_networkmanager_recovery_after_seconds=2' \
    -e 'wifi_watchdog_reboot_after_seconds=0' \
    -e '{"wifi_watchdog_internet_probe_addresses": ["1.1.1.1", "8.8.8.8"]}' \
    -e 'wifi_watchdog_networkmanager_service_name=NetworkManager.service' \
    -e "wifi_watchdog_monotonic_clock_path=${monotonic_clock_file}" \
    -e 'wifi_watchdog_reboot_mode_path="" wifi_watchdog_required_reboot_mode=""' >/dev/null

run_watchdog "${recovery_retry_script}" 'wlan0:disconnected' 4 0 '' 1

grep -Fxq 'restart NetworkManager.service' "${test_log}"

run_watchdog "${recovery_retry_script}" 'wlan0:disconnected' 4 0 '' 0 1

networkmanager_retries=$(grep -Fxc 'restart NetworkManager.service' "${test_log}" || true)
if (( networkmanager_retries < 2 )); then
    printf 'watchdog did not retry a failed NetworkManager restart\n' >&2
    exit 1
fi

run_watchdog "${recovery_retry_script}" 'wlan0:disconnected' 5

connection_retries=$(grep -Fxc 'device connect wlan0' "${test_log}" || true)
if (( connection_retries < 2 )); then
    printf 'watchdog did not retry the connection after NetworkManager restart\n' >&2
    exit 1
fi

ansible localhost -c local -m ansible.builtin.template \
    -a "src=${role_root}/templates/wifi-connectivity-watchdog.sh.j2 dest=${escalation_retry_script} mode=0750" \
    -e 'wifi_watchdog_interface=wlan0 wifi_watchdog_connection=""' \
    -e 'wifi_watchdog_gateway_probe="" wifi_watchdog_dns_probe=example.com' \
    -e 'wifi_watchdog_check_interval_seconds=1' \
    -e 'wifi_watchdog_connection_recovery_after_seconds=1' \
    -e 'wifi_watchdog_networkmanager_recovery_after_seconds=2' \
    -e 'wifi_watchdog_reboot_after_seconds=3' \
    -e '{"wifi_watchdog_internet_probe_addresses": ["1.1.1.1", "8.8.8.8"]}' \
    -e 'wifi_watchdog_networkmanager_service_name=NetworkManager.service' \
    -e "wifi_watchdog_monotonic_clock_path=${monotonic_clock_file}" \
    -e 'wifi_watchdog_reboot_mode_path="" wifi_watchdog_required_reboot_mode=""' >/dev/null

run_watchdog "${escalation_retry_script}" 'wlan0:disconnected' 5 0 '' 0 1

grep -Fxq 'restart NetworkManager.service' "${test_log}"
grep -Fxq 'ping -c 1 -W 2 1.1.1.1' "${test_log}"
if grep -Fxq reboot "${test_log}"; then
    printf 'watchdog rebooted despite general internet reachability\n' >&2
    exit 1
fi

run_watchdog "${escalation_retry_script}" 'wlan0:disconnected' 5 0 '' 0 1 1

grep -Fxq reboot "${test_log}"

printf '%s\n' warm > "${reboot_mode_file}"

ansible localhost -c local -m ansible.builtin.template \
    -a "src=${role_root}/templates/wifi-connectivity-watchdog.sh.j2 dest=${reboot_guard_script} mode=0750" \
    -e 'wifi_watchdog_interface=wlan0 wifi_watchdog_connection=""' \
    -e 'wifi_watchdog_gateway_probe="" wifi_watchdog_dns_probe=example.com' \
    -e 'wifi_watchdog_check_interval_seconds=1' \
    -e 'wifi_watchdog_connection_recovery_after_seconds=1' \
    -e 'wifi_watchdog_networkmanager_recovery_after_seconds=2' \
    -e 'wifi_watchdog_reboot_after_seconds=3' \
    -e '{"wifi_watchdog_internet_probe_addresses": ["1.1.1.1", "8.8.8.8"]}' \
    -e 'wifi_watchdog_networkmanager_service_name=NetworkManager.service' \
    -e "wifi_watchdog_monotonic_clock_path=${monotonic_clock_file}" \
    -e "wifi_watchdog_reboot_mode_path=${reboot_mode_file} wifi_watchdog_required_reboot_mode=cold" >/dev/null

run_watchdog "${reboot_guard_script}" 'wlan0:disconnected' 5 0 '' 0 0 1

if grep -Fxq reboot "${test_log}"; then
    printf 'watchdog rebooted without the required active reboot mode\n' >&2
    exit 1
fi

printf '%s\n' cold > "${reboot_mode_file}"

run_watchdog "${reboot_guard_script}" 'wlan0:disconnected' 5 0 '' 0 0 1

grep -Fxq reboot "${test_log}"
