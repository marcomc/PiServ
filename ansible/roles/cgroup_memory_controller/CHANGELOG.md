# Changelog

All notable changes for the cgroup_memory_controller Ansible role are
documented here.

## 0.1.0 - Unreleased

### Added

- Added Debian-family cgroup v2 memory-controller management through a full,
  validated copy of the vendor Device Tree Blob.
- Added exact `cgroup_disable=memory` removal with `fdtput`, post-write
  validation with `fdtget`, and marked `device_tree=<filename>` selection.
- Added initial boot-artifact backups, explicit rollback, and optional runtime
  assertions without modifying the vendor DTB.
- Added a kernel post-install hook that refreshes the managed DTB after a
  declared firmware-refresh hook updates the vendor DTB, with optional active
  reboot-mode verification before regeneration.
- Added fail-closed backup validation before managed boot-state rollback.
- Added recoverable initial backup-set creation so failed fresh copies or
  validation leave no partial recovery generation behind, while managed boot
  state cannot be accepted as a new pre-policy recovery baseline.
- Added serialized boot-state mutations across reconciliation and kernel-hook
  fallback rollback.
- Added verified private source snapshots with bounded retries so each
  reconciliation derives status, checksum, and managed boot artifacts from one
  stable firmware generation through transaction finalization.
- Added attested disabled-role rollback with postflight verification before
  removing the helper and kernel hook.
- Added consumer input checks for managed-DTB name/path consistency, atomic
  boot arguments, and trusted root-owned paths used by privileged helpers.
- Added Galaxy-ready metadata, role documentation, validation, and release
  instructions.
