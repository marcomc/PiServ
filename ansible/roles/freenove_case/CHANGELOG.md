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
- Added direct Ansible-side LED and fan hardware apply support through
  Freenove's expansion-board API.
- Changed LED and fan custom background tasks to opt-in defaults so they do
  not override Ansible-applied hardware values.
- Changed Close/off LED mode handling to also clear stored RGB values on the
  expansion board.
- Documented that FNK0100 exposes no separate software control for fan LEDs.
- Added optional touchscreen idle backlight control through a user `swayidle`
  service.
- Documented that the small OLED color is fixed by the physical monochrome
  module.
- Generalized role defaults and documentation so project-specific values live
  outside the Galaxy-ready role.

### Fixed

- Skip the I2C firmware-change reboot in Ansible check mode while preserving
  normal-mode reboot behavior.
