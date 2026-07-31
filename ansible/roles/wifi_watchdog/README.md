# Ansible Role: Wi-Fi Watchdog

Manage a systemd watchdog that monitors NetworkManager Wi-Fi connectivity and
recovers it progressively when a network becomes unavailable.

## Table of Contents

- [Purpose](#purpose)
- [Requirements](#requirements)
- [Installation](#installation)
- [Role Variables](#role-variables)
- [Example Playbook](#example-playbook)
- [Recovery Policy](#recovery-policy)
- [Supported Platforms](#supported-platforms)
- [Validation](#validation)
- [Release Notes](#release-notes)
- [License](#license)
- [Support](#support)

## Purpose

The role installs a root-owned service that continuously verifies:

- NetworkManager reports the configured Wi-Fi interface as connected.
- The IPv4 default gateway for the configured Wi-Fi interface, or an explicitly
  configured gateway, responds to an interface-bound ping.
- A configured DNS name resolves through the system resolver and an IPv4 result
  responds to an interface-bound ping.

After a continuous offline period it restarts the NetworkManager connection,
then NetworkManager itself. Host reboot is deliberately disabled by default.
When `/usr/local/sbin` does not exist, the role creates it as `root:root` mode
`0755`; existing script and service directories are left unchanged. The role
requires `/usr`, `/usr/local`, `/usr/local/sbin`, and the system unit directory
to be root-owned and not writable by group or other users because the service
executes as root.

## Requirements

| Requirement | Value |
| --- | --- |
| Service manager | systemd |
| Network stack | NetworkManager and `nmcli` |
| Runtime commands | `awk`, `bash`, `getent`, `ip`, `logger`, `ping`, `systemctl` |
| Ansible | `ansible-core >= 2.15` |
| Privilege escalation | Required |
| Facts | `gather_facts: true` |

## Installation

After the role is published to Ansible Galaxy:

```sh
ansible-galaxy role install marcomc.wifi_watchdog
```

Pinned install example:

```sh
ansible-galaxy role install marcomc.wifi_watchdog,0.1.0
```

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `wifi_watchdog_service_name` | `wifi-connectivity-watchdog.service` | Managed systemd service name |
| `wifi_watchdog_service_path` | `/etc/systemd/system/{{ wifi_watchdog_service_name }}` | Managed unit path directly under `/etc/systemd/system`; filename must equal `wifi_watchdog_service_name` |
| `wifi_watchdog_script_path` | `/usr/local/sbin/wifi-connectivity-watchdog` | Managed script path directly under `/usr/local/sbin` |
| `wifi_watchdog_interface` | `wlan0` | Wi-Fi interface monitored through NetworkManager |
| `wifi_watchdog_connection` | `""` | Connection name; empty lets NetworkManager choose an eligible saved Wi-Fi profile |
| `wifi_watchdog_gateway_probe` | `""` | Gateway to ping through the Wi-Fi interface; empty uses that interface's IPv4 default route |
| `wifi_watchdog_dns_probe` | `example.com` | Name resolved through the system resolver and reached through the Wi-Fi interface; empty disables this check |
| `wifi_watchdog_check_interval_seconds` | `30` | Check interval while connectivity is healthy |
| `wifi_watchdog_connection_recovery_after_seconds` | `300` | Offline duration before connection restart |
| `wifi_watchdog_networkmanager_recovery_after_seconds` | `600` | Offline duration before NetworkManager restart |
| `wifi_watchdog_reboot_after_seconds` | `0` | Offline duration before reboot; `0` disables it |
| `wifi_watchdog_networkmanager_service_name` | `NetworkManager.service` | Service restarted at the second escalation level |
| `wifi_watchdog_monotonic_clock_path` | `/proc/uptime` | Linux kernel monotonic-uptime file used for recovery timing |

Set `wifi_watchdog_reboot_after_seconds` only after observing the lower
recovery levels on the target network. A reboot can hide a router or mesh
problem and can interrupt work running on the host.

## Example Playbook

```yaml
---
- name: Configure Wi-Fi recovery
  hosts: wifi_hosts
  gather_facts: true
  roles:
    - role: marcomc.wifi_watchdog
      vars:
        wifi_watchdog_interface: wlan0
        wifi_watchdog_connection: office-wifi
        wifi_watchdog_connection_recovery_after_seconds: 300
        wifi_watchdog_networkmanager_recovery_after_seconds: 600
        wifi_watchdog_reboot_after_seconds: 0
```

To let NetworkManager select any available saved Wi-Fi profile, omit
`wifi_watchdog_connection` as shown above. A profile must remain eligible for
automatic activation and have usable saved credentials. Set the variable only
when a host must always reconnect to one named profile.

To preserve an existing local service identity during migration, override the
service name and script filename in the consumer playbook. The script must
remain directly under `/usr/local/sbin` and the service unit path must remain
directly under `/etc/systemd/system`. Those consumer-specific values are not
required by the role.

## Recovery Policy

```text
link + gateway + DNS healthy
        |
        v
reset offline timer

offline for configured duration
        |
        +-- connection restart
        |
        +-- NetworkManager restart
        |
        +-- optional host reboot
```

The timer resets only when all enabled checks succeed. Recovery messages are
logged with the `wifi-connectivity-watchdog` journal identifier.

The `nmcli` status command uses the C locale before its output is parsed. The
offline timer reads Linux kernel monotonic uptime from `/proc/uptime`, so
wall-clock corrections cannot skip or delay an escalation level. The DNS probe
requires an IPv4 response through the monitored interface; use a hostname whose
resolved addresses allow ICMP echo replies.

## Supported Platforms

| Platform | Status |
| --- | --- |
| Raspberry Pi OS Trixie / Debian 13 with NetworkManager | Tested live |
| Other systemd hosts with NetworkManager | Compatible by design; not yet tested |

## Validation

Run from the standalone role root:

```sh
ansible-playbook --syntax-check tests/test.yml
tests/test-watchdog.sh
ansible-lint .
```

On a fresh target, check mode predicts missing parent directories and skips
template, startup, and restart work that would require those directories or a
unit to exist. A converged target still checks the systemd enablement and
startup state.

Render the script with representative variables before running ShellCheck:

```sh
ansible localhost -c local -m ansible.builtin.template \
  -a 'src=templates/wifi-connectivity-watchdog.sh.j2 dest=/tmp/wifi-watchdog.sh' \
  -e 'wifi_watchdog_interface=wlan0 wifi_watchdog_connection=test-wifi' \
  -e 'wifi_watchdog_gateway_probe="" wifi_watchdog_dns_probe=example.com' \
  -e 'wifi_watchdog_check_interval_seconds=30' \
  -e 'wifi_watchdog_connection_recovery_after_seconds=300' \
  -e 'wifi_watchdog_networkmanager_recovery_after_seconds=600' \
  -e 'wifi_watchdog_reboot_after_seconds=0' \
  -e 'wifi_watchdog_networkmanager_service_name=NetworkManager.service' \
  -e 'wifi_watchdog_monotonic_clock_path=/proc/uptime'
shellcheck --enable=all /tmp/wifi-watchdog.sh
```

## Release Notes

See [CHANGELOG.md](CHANGELOG.md). Publication steps are documented in
[docs/releasing.md](docs/releasing.md).

## License

MIT. See [LICENSE](LICENSE).

## Support

The role is maintained by Marco Massari Calderone <marco@marcomc.com>. Until
it is exported to a standalone repository, report issues in the consumer
project that carries the role.
