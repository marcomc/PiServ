# Changelog

All notable changes for the cgroup_memory_controller Ansible role are
documented here.

## 0.1.0 - Unreleased

### Added

- Added Debian-family cgroup v2 memory-controller management through a
  validated Device Tree overlay.
- Added source-DTB checks, offline merge validation, initial boot-artifact
  backups, explicit rollback, and optional runtime assertions.
- Added a kernel post-install hook that refreshes the overlay after a declared
  firmware-refresh hook.
- Added Galaxy-ready metadata, role documentation, validation, and release
  instructions.
