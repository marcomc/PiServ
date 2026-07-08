# Changelog

All notable changes for the msmtp Ansible role are documented here.

## 0.1.0 - Unreleased

### Added

- Added Galaxy-ready standalone role metadata.
- Added argument specifications for role variables.
- Added package installation for `msmtp`, `msmtp-mta`, and `bsd-mailx`.
- Added `managed`, `create`, and `unmanaged` management modes for
  `/etc/msmtprc` and aliases.
- Added metadata hardening for existing operator-managed config and aliases.
- Added `dpkg-statoverride` support for setgid system-config access.
- Added optional `/usr/local/bin/msmtp-system` compatibility wrapper.
- Added account and aliases templates inspired by
  `fauch922.ansible_msmtp_setup`.
- Added release runbook for exporting the role to a standalone Galaxy repo.
