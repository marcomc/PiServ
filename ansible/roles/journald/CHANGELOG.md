# Changelog

All notable changes for the journald Ansible role are documented here.

## 0.1.0 - Unreleased

### Added

- Added Debian-family journald drop-in management with persistent, volatile,
  and automatic storage modes.
- Added optional compression, disk-use, free-space, file-size, retention, and
  synchronization-interval settings.
- Added ordered restart and runtime-journal flush handling after configuration
  changes.
- Added Galaxy-ready metadata, role documentation, validation, and release
  instructions.

### Fixed

- Skip drop-in rendering when check mode only predicts a missing parent
  directory, allowing configured paths to be checked without failure.
