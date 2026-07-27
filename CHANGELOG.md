# Changelog

All notable project changes are documented here.

## 0.2.0 - Unreleased

### External SSD Storage

- Repartitioned the verified ASM246X external disk as one GPT partition spanning
  3.64 TiB and formatted it as journaled ext4 labeled `external-data`.
- Added UUID-based mounting at `/mnt/external-data` with `nodev`, `nosuid`,
  and optional-device boot behavior, while destructive actions verify a local
  stable by-id device identity.
- Added the dedicated `external-data` group, shared ACL policy, restricted
  backup directory, and non-destructive convergence playbook.
- Added the external SSD storage decision record and operator runbook.

### Cockpit Web Console

- Added the Cockpit HTTPS web console, socket activation, and a local login-page
  assertion to the PiServ base role.
- Kept the package install minimal by excluding optional storage, NetworkManager,
  and package-management modules.
- Allowed Cockpit TCP port `9090` only from the current IPv4 LAN while retaining
  the existing Tailnet interface policy and PAM-backed `admin` authentication.
- Added the Cockpit runbook and architecture decision, including the expected
  self-signed certificate bootstrap behavior.

### Glances Observability

- Added a PiServ-managed Glances API service with hardware sensor support and
  its required Uvicorn and Jinja2 webserver runtimes and HTTP Basic
  authentication.
- Bound the API to IPv4 for LAN observability and Home Assistant, disabled the
  broken Debian 13 web UI, and allowed TCP `61208` from the current LAN in UFW
  under the existing Tailnet ingress policy.
- Hardened the service with a dynamic user, private state and runtime
  directories, systemd filesystem and privilege restrictions, a salted password
  hash, and a root-only credential bootstrap for Home Assistant.
- Added authenticated and unauthenticated API-response assertions plus
  listener-scope validation to the base playbook.
- Recorded acceptance of the direct, HTTP Basic-authenticated API exposure only
  to the trusted LAN and ACL-controlled Tailnet boundary while Debian security
  updates are applied.

### Home Assistant MQTT Agent

- Replaced the project-local role with the published and version-pinned Galaxy
  role `marcomc.ha_mqtt_agent`.
- Updated the role pin to `v0.1.1` so read-only validation probes run during
  Ansible check mode.
- Added a PiServ playbook that preserves the host MQTT configuration and
  validates the `0.3.0` agent, broker connectivity, service state, and
  Raspberry Pi 5 firmware telemetry.
- Documented the service-configured MQTT doctor command rather than the
  misleading root-user default-config invocation.

### Host Baseline Follow-Ups

- Replaced routine raw unattended-upgrades transcripts with a mobile-readable
  multipart digest that shows status, reboot state, and `previous -> installed`
  package versions while retaining full logs on PiServ and native error alerts.
- Accepted `admin` as the only human sudo account for now and made it the
  inventory connection user for current user-scoped workloads;
- Added project-owned `wayvnc` startup automation that captures the physical
  Freenove touchscreen output `DSI-1`, including a control-socket assertion
  that the touchscreen is actively captured rather than merely detected.
- Recorded the Freenove cleanup state: the managed checkout is under `/opt`,
  I2C devices are healthy, managed hardware readback is idempotent, and the
  always-on blue fan LEDs are a documented physical limitation.
- Added decision records and runbooks for the account, VNC, and Freenove
  follow-up work.
- Replaced the indefinite WayVNC `SIGSEGV` monitor with a version-triggered
  three-restart acceptance test and explicit resolution criteria.
- Corrected pCloud and RaiPlaySound read-only validation probes so role check
  mode evaluates their live state before assertions run.
- Hardened VNC selector path validation, aligned its wait budget with the role
  timeout, and re-ran it after either vendor VNC service starts without
  restarting the current WayVNC process during deployment. Selector unit
  changes and missing installation links now reconcile both systemd links.
- Recorded the installed TigerVNC client and added its direct and Tailscale
  connection acceptance test to the current backlog.

### Tailscale Remote Access

- Added the pinned `artis3n.tailscale` Galaxy collection dependency and switched
  PiServ Tailscale installation to the upstream `artis3n.tailscale.machine`
  role.
- Added a PiServ Tailscale playbook with the stable machine name `piserv`.
- Disabled acceptance of advertised subnet routes so PiServ always replies to
  local-LAN clients through its physical network interface.
- Configured PiServ as a high-availability subnet router for its local IPv4 LAN
  with forwarding, default Tailscale SNAT, and an exact route advertisement.
- Ensured manual and auth-key first login apply the complete HA subnet-router
  policy.
- Added a Tailscale access runbook covering manual browser login, verification,
  diagnostics, recovery, route-approval and failover follow-up, key-expiry
  trade-offs, and firewall integration.
- Documented that PiServ keeps standard OpenSSH as the administration path and
  does not enable Tailscale SSH for now.

### Firewall Policy

- Added a commit-pinned `marcomc/ansible-ufw` fork integration.
- Declared its pinned `ansible.posix` dependency and configured the firewall
  playbook to use the inventory user's sudo privileges.
- Added UFW rule mutation pass-through for bounded deletion and ordered
  insertion, with Debian 13 and Trixie validation in the fork.
- Moved PiServ-only preflight, service enforcement, and runtime validation to
  imported project task files alongside the firewall playbook.
- Added a PiServ firewall playbook with default-deny incoming and routed
  policies, default-allow outgoing policy, low-volume logging, and runtime
  validation.
- Allowed IPv4 LAN SSH, VNC, and mDNS; Tailscale interface ingress; and direct
  Tailscale UDP while keeping unsolicited LAN, including IPv6, traffic blocked.
- Allowed routed Tailscale IPv4 traffic only to the local IPv4 LAN for subnet
  router operation.
- Added the firewall decision record and operator runbook, including Tailscale
  netfilter ownership, additive UFW rule behavior, validation, and recovery.

## 0.1.0 - 2026-07-09

Initial PiServ release for reproducing and operating the Raspberry Pi 5 server
at `PiServ.local`.

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
- Configured the baseline to preserve `admin` SSH/sudo access, disable SSH root
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
- Installed RaiPlaySound CLI for the `admin` user with a user-scoped systemd
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
