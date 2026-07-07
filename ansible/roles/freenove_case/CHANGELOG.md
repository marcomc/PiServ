# Changelog

All notable changes for the Freenove Case Ansible role are documented here.

## 0.1.0 - Unreleased

### Added

- Added Galaxy-ready standalone role metadata.
- Added argument specifications for role variables.
- Added Freenove FNK0100 post-OS automation.
- Added desktop launcher management.
- Added optional Freenove background service management.
- Added optional PiBenchmarks clone and one-shot benchmark support.
- Added optional PCIe Gen3 firmware configuration.
- Added validation for I2C, Python imports, and Freenove Python source syntax.
- Added release runbook for exporting the role to a standalone Galaxy repo.
- Split role tasks into scoped task files with `tasks/main.yml` as the
  orchestrator.
- Added `freenove_case_repo_update` so repeat runs do not fetch from GitHub
  unless explicitly requested.
- Added explicit firmware config permission management.
- Added `freenove_case_source_mode` with `git`, `controller_copy`, and
  `archive_url` installation strategies.
- Changed the default install directory to `/opt/freenove-case`.
- Added optional management of Freenove `Code/app_config.json` for reproducible
  LED, fan, and OLED background behavior.
- Added a Freenove expansion-controller preflight before background service
  management.
