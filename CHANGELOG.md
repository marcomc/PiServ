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
- Built and installed source-built `pcloudcc` on PiServ.
- Added a Galaxy-ready `pcloudcc` Ansible role with metadata, argument specs,
  role docs, release runbook, tests, and role license file.
- Added a Debian 13 `arm64` source patch for building the official pCloud
  console client on PiServ.
- Added the `pcloudcc-install.yml` playbook and validated idempotent client
  installation on PiServ.
- Added a `pcloudcc_version` role default for expected pCloud console-client
  version validation.
- Documented the `pcloudcc` first-login blocker for TOTP-enabled pCloud
  accounts.
- Added and installed patched `pcloudcc` CLI support for TOTP and recovery-code
  prompts.
- Validated patched `pcloudcc` TOTP login, pCloud FUSE mount, and local
  podcast-target write/read/delete on PiServ.
- Added `pcloudcc` credential hardening for the saved pCloud state directory.
- Added optional user-scoped `pcloudcc` systemd service management to the
  `pcloudcc` Ansible role.
- Validated credential-free `pcloudcc.service` startup and saved-auth restart
  on PiServ.
- Added `scripts/check-pcloudcc-health.sh` and the remote pCloud health-check
  script for mount, service, and write/read/delete validation.
- Added `pcloudcc-health-check.yml` for Ansible-driven pCloud health checks.
- Validated `pcloudcc.service` reboot recovery and external pCloud visibility
  from the Mac pCloud Drive path.
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
- Made Ansible role defaults and role documentation agnostic of PiServ-specific
  host values so roles remain suitable for standalone Galaxy publication.
- Changed the `pcloudcc` CLI patch so saved-auth startup can run without an
  account email in the service command and fails visibly when interactive login
  would be required.
