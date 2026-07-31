# Changelog

All notable changes for the Wi-Fi Watchdog Ansible role are documented here.

## 0.1.0 - Unreleased

### Added

- Added NetworkManager Wi-Fi link, gateway, and optional DNS monitoring.
- Added progressive recovery from connection restart to NetworkManager restart.
- Added opt-in host reboot escalation, disabled by default.
- Added Galaxy-ready metadata, standalone documentation, validation guidance,
  and publication instructions.
- Added safe handling for missing configurable script and service parent paths.
- Added input-range and trusted-parent validation before root-managed rendering.
- Added a regression test for reconnecting without a configured Wi-Fi profile.
- Bound the automatic gateway lookup and gateway ping to the monitored Wi-Fi
  interface so another interface cannot mask a Wi-Fi outage.
- Forced the C locale for parsed `nmcli` interface state and replaced the
  wall-clock offline timer with Linux kernel monotonic uptime.
- Rejected unit paths whose filename differs from the configured service name.
- Required the DNS probe's resolved IPv4 address to respond through the
  monitored Wi-Fi interface.
- Performed configurable parent and unit inspection with privilege escalation,
  and skipped systemd startup and restart only when fresh check mode predicts a
  new unit.
