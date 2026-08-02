# Changelog

All notable changes for the Freenove Case Ansible role are documented here.

## 0.1.0 - Unreleased

### Implemented

- Galaxy-ready metadata, argument specifications, standalone documentation,
  validation, release guidance, and scoped task files.
- Freenove FNK0100 post-OS automation for packages, I2C, source installation,
  desktop launchers, firmware permissions, and runtime validation.
- `git`, `controller_copy`, and `archive_url` source strategies, with opt-in Git
  refresh and `/opt/freenove-case` as the generic installation default.
- Optional background service, managed `Code/app_config.json`, expansion-board
  preflight, direct LED/fan hardware reconciliation, touchscreen idle control,
  PCIe Gen3 configuration, and PiBenchmarks execution.
- Conservative LED and fan task defaults that preserve Ansible-applied hardware
  state, including Close/off RGB clearing and FNK0100 fan-LED limitations.
- An opt-in, atomically rendered task-manager runtime artifact that fixes the
  upstream SIGTERM handler without modifying the installed upstream source.
- Optional verified active-kernel reboot mode before an I2C change triggers an
  automatic reboot; check mode never performs the reboot.
