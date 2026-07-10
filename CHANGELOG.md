# Changelog

All notable project changes are documented here.

## 0.1.0 - 2026-07-09

Initial PiServ release for reproducing and operating the Raspberry Pi 5 server
at `piserv.example.com`.

### Documentation and Operating Model

- Established the project documentation set: `README.md`, `AGENTS.md`,
  `TODO.md`, `CHANGELOG.md`, private license notice, runbooks, decisions, and
  implementation tracks.
- Documented the canonical local repository path, target host facts, SSH access
  model, and production-first operating workflow.
- Added operator runbooks for server access, NVMe migration, Freenove FNK0100K
  setup, pCloud storage, RaiPlaySound scheduling, system baseline inventory,
  base security hardening, and system mail notifications.
- Clarified the pre-hardening scope of the baseline inventory and refreshed
  release validation commands to cover all first-party Markdown and shell files.
- Refreshed pCloud, RaiPlaySound, and system-mail documentation to match the
  validated TOTP, create-only config, and operator-managed mail contracts.
- Added decision records for the project operating model, NVMe primary boot,
  pCloud-backed podcast storage, local repository path, Freenove background
  control, RaiPlaySound direct-write scheduling, base security posture, and
  system mail notifications.

### Host Baseline

- Added the PiServ Ansible inventory and base host playbook.
- Added a project-local `base` Ansible role for SSH hardening, service
  management, unattended upgrades, automatic reboot scheduling, cloud-init
  disablement, and reboot notifications.
- Tightened the `base` role orchestration to use dynamic task includes for
  conditional stateful phases.
- Configured the baseline to preserve `operator` SSH/sudo access, disable SSH root
  login, disable unneeded CUPS, `rpcbind`, and NFS helper exposure, and keep
  Bluetooth available.
- Changed the mail bootstrap path to harden operator-created mail config files
  instead of creating empty `/etc/msmtprc` or `/etc/aliases` files, and made boot
  notifications skip empty mail configs.
- Added a system baseline inventory covering OS, kernel, firmware, storage,
  network, packages, enabled services, listening sockets, and security inputs.

### Boot and Storage

- Added guarded shell and Ansible automation to migrate PiServ from microSD to
  NVMe.
- Configured NVMe as the primary boot and root filesystem with microSD fallback.
- Added safeguards for destructive NVMe reimaging, remote execution helpers,
  boot-order checks, filesystem migration, and post-migration validation.
- Removed fixed `/tmp` executable staging from migration helpers and tightened
  post-reboot verification to require `/` and `/boot/firmware` on the expected
  target partitions.
- Documented the 128 GB NVMe-backed server layout and recovery path.

### Freenove FNK0100K Case

- Added a reusable `freenove_case` Ansible role and PiServ playbook for
  Freenove FNK0100K post-OS setup.
- Automated runtime packages, I2C enablement, Freenove source deployment from
  the controller-managed vendor copy, desktop launchers, background service
  setup, and runtime config management.
- Added direct Ansible-side LED and fan hardware application support.
- Configured PiServ hardware defaults for disabled case LEDs, automatic fan
  thresholds, OLED display timing, and touchscreen idle backlight control.
- Added target/runtime validation, expansion-controller preflight checks, role
  metadata, argument specs, tests, release documentation, and role license.
- Avoided ownership changes to existing Freenove install parent directories and
  enabled linger for the optional touchscreen idle user service.

### pCloud Podcast Storage

- Added a reusable `pcloudcc` Ansible role and PiServ install playbook for the
  official pCloud console client.
- Automated Debian 13 `arm64` source builds, pinned expected client version
  validation, runtime package installation, mount-root preparation, and source
  patch application.
- Added source patches for Debian 13 `arm64` build support and CLI TOTP or
  recovery-code prompts.
- Applied pCloud source patches through argument-vector commands instead of a
  rendered shell block.
- Added a fail-closed pinned source revision check for existing pCloud checkouts.
- Added saved-credential hardening and credential-free user-scoped systemd
  service management for the pCloud FUSE mount.
- Added local and remote health-check scripts plus an Ansible health-check
  playbook for service, mount, and write/read/delete validation.
- Documented the selected pCloud EU region, mount root `/mnt/pcloud`, and
  RaiPlaySound target
  `/mnt/pcloud/My Music/Podcasts/raiplaypodcast`.

### RaiPlaySound Scheduled Sync

- Added a reusable `raiplaysound_cli` Ansible role and PiServ playbook for
  scheduled podcast synchronization.
- Installed RaiPlaySound CLI for the `operator` user with a user-scoped systemd
  service and daily timer.
- Configured scheduled syncs to write directly to the pCloud-backed podcast
  target after the pCloud health check passes.
- Added managed, create-only, and unmanaged config modes with partial config
  merging so PiServ can preserve manual server-side edits.
- Added non-secret email wiring for newly created PiServ configs through the
  system `msmtp` compatibility wrapper.

### System Mail

- Added a reusable `msmtp` Ansible role for package installation, managed or
  operator-managed configuration, aliases, metadata hardening, and validation.
- Added `/usr/local/bin/msmtp-system` for tools that pass `/etc/msmtprc` through
  explicit `--file`.
- Quoted compatibility-wrapper paths when rendering the `msmtp-system` shell
  script.
- Documented operator-managed SMTP credentials, local alias handling,
  unattended-upgrades reporting, reboot notifications, and Gmail app password
  setup.

### Reusable Ansible Roles

- Prepared the `freenove_case`, `pcloudcc`, `raiplaysound_cli`, and `msmtp`
  roles for standalone reuse with defaults, metadata, argument specs, tests,
  README files, changelogs, release notes, and role license files.
- Kept reusable role defaults and documentation agnostic of PiServ-specific
  hostnames, paths, and project-only assumptions.
- Documented `base` as the project-local exception to the reusable-role policy.
- Added a repository shell validation script that covers tracked shebang files
  and rendered shell templates.
- Ignored local `.ansible/` cache directories created by Ansible tooling.
