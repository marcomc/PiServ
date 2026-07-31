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
