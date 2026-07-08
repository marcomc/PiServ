# Changelog

All notable changes for the raiplaysound_cli Ansible role are documented here.

## 0.1.0 - Unreleased

### Added

- Added standalone role metadata and argument specs.
- Added Debian runtime dependency installation.
- Added source checkout and standalone `make install` support.
- Added config-file management for the runtime user.
- Added managed, create-only, and fully unmanaged config-file modes.
- Added explicit merging of partial config overrides with role defaults.
- Added optional user-scoped systemd service and timer management.
- Added validation so existing config parent paths are not overwritten or
  chmodded by the role.
