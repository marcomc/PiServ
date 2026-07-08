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
- Added idempotent Freenove FNK0100K post-OS Ansible role and playbook.
- Prepared the Freenove role for standalone Ansible Galaxy publication with
  metadata, argument specs, role docs, release runbook, tests, and a role
  license file.
- Added Freenove role source modes for Git, controller copy, and archive URL
  installs.
- Documented manual `pcloudcc -p -s` credential bootstrap for PiServ.
- Documented the European Union pCloud data region for PiServ `pcloudcc`
  validation without embedding the account email.
- Added a pCloud `pcloudcc` implementation track for live build, validation,
  systemd, and automation work.
- Added Ansible-managed Freenove background service and runtime configuration
  for LED, fan, and OLED control.
- Added a Freenove expansion-controller preflight to avoid enabling a failing
  background service.
- Added the Freenove background-control decision record.
- PiServ to boot from NVMe with microSD fallback.
- Selected `pcloudcc` as the pCloud storage backend for scheduled podcast jobs.
- Set the pCloud mount root to `/mnt/pcloud` and the RaiPlaySound podcast
  target to `/mnt/pcloud/My Music/Podcasts/raiplaypodcast`.
- Changed PiServ Freenove installation to copy the local vendored Freenove
  checkout from the Ansible controller into `/opt/freenove/`.
- Added direct Ansible-side Freenove LED and fan hardware apply support so
  playbook variable changes do not require the desktop app.
- Changed PiServ Freenove LED and fan custom tasks to disabled so direct
  Ansible-applied hardware settings remain authoritative.
- Changed PiServ Freenove LED mode to Follow with a blue base color for live
  inspection.
- Raised PiServ Freenove automatic fan thresholds to `40 C` and `65 C`,
  keeping fan mode `0`.
- Changed PiServ Freenove LED mode to Breathing with a blue base color.
- Changed PiServ Freenove LED color to very dim white.
- Changed PiServ Freenove OLED screen display times to `5.0` seconds.
- Changed PiServ Freenove LED mode to Close/off and cleared all stored RGB
  groups to `0,0,0`.
- Documented that PiServ's blue fan LEDs remain on even when FNK0100 fan PWM
  is temporarily set to off.
- Added Ansible-managed touchscreen idle backlight control with a two-minute
  PiServ timeout.
- Documented that the small Freenove OLED is monochrome and cannot be changed
  to amber in software.
