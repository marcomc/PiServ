# Changelog

All notable project changes are documented here.

## Unreleased

### Added

- Initialized project documentation and operating rules.
- Added initial server facts for PiServ.
- Added documentation folders for runbooks and decisions.
- Added private project license notice.
- Added guarded shell automation for migrating PiServ from microSD to NVMe.
- Added an Ansible inventory and guarded NVMe migration playbook.
- Added NVMe migration runbook and primary-boot decision record.
- Added pCloud-backed podcast storage decision record.
- Added `pcloudcc` storage validation runbook.
- Added vendored Freenove FNK0100 reference resources.
- Added Freenove FNK0100K post-OS setup runbook.
- Added canonical local repository path guidance.
- Added `.gitignore` exclusion for `vendor/freenove/`.
- Documented the exact Freenove Git clone command in the README.
- Replaced personal absolute paths with `$HOME`-relative paths.

### Changed

- Renamed the local project from PiServ to PiServ.
- Corrected the documented hostname from `piserv.local` to `piserv.example.com`.
- Migrated PiServ to boot from NVMe with microSD fallback.
- Selected `pcloudcc` as the pCloud storage backend for scheduled podcast jobs.
