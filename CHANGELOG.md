# Changelog

## Unreleased

### Hermes Desktop

- Advanced the locked Hermes revision to Desktop backend contract 6 and
  documented the distinction between Desktop SSH and Remote URL modes.
- Added a confirmation-gated, standalone dashboard credential-rotation
  playbook that avoids a full Hermes convergence.
- Allowed the immediately preceding, root-owned installer checksum only during
  the pinned Hermes installer migration.

### Hermes MCP SSH Access

- Added a password-locked `codex-hermes-mcp` SSH principal that runs
  only the Hermes MCP stdio server as `hermes-agent` through a root-owned
  wrapper and exact no-argument sudoers rule.
- Added manual-key and automatic-copy modes. Automatic copy is enabled by
  default and converts each current `admin` public key into a restricted
  forced-command key; manual mode creates an empty private key file once and
  preserves subsequent operator edits.
- Documented Codex registration, validation, and revocation for SSH-only MCP
  access without a LAN or Tailnet MCP listener.
- Added a distinct `codex-hermes-delegate` SSH principal and bounded stdio MCP
  adapter that exposes `delegate_task(prompt)` and runs one Hermes agent turn
  with its persistent identity, configured tools, and Home Assistant MCP.
- Isolated the delegated CLI policy from the dashboard and conversations MCP;
  the native Hermes loop receives delegation, file, memory, session search,
  skills, terminal, todo, and configured Home Assistant MCP tools rather than
  stateless MCP callbacks. A delegation-only config bypasses non-interactive
  approval staging without changing dashboard or conversations policy.
- Kept the existing `hermes-piserv` messaging bridge bound to
  `hermes mcp serve`; delegation uses a separately named client entry without
  adding a network listener, shell access, general sudo, or credential output.

## [0.5.0] - 2026-08-11

### Hermes Home Assistant and Apple Home

- Activated the PiServ Hermes smart-home policy with protected mode,
  activity-scoped autonomy, and confirmation for critical physical actions.
- Validated an isolated Hermes backup/import MCP proof and a reversible
  Home Assistant-to-Apple Home acceptance cycle with the policy active.
- Confirmed manual Siri control and read-only observation of an Apple Home-only
  accessory; documented that advanced climate controls require a future
  allowlisted MCP extension.

- Added a Mac-side acceptance harness that drives Hermes through its SSH CLI,
  verifies Home Assistant and Apple Home convergence through HomeClaw, restores
  reversible test entities, and writes local text and JSON reports.
- Added a local allowlist example, release runbook, and accepted decision for
  activity-scoped Hermes autonomy, critical-action confirmation, and HomeClaw's
  read-only observer role.
- Validated a live reversible light operation: Hermes changed the Home Assistant
  entity, HomeClaw observed the corresponding Apple Home state, and Hermes
  restored the original state through the same MCP path.
- Repeated the same acceptance test after restarting the Hermes dashboard;
  Home Assistant and HomeClaw again confirmed both the requested state and the
  restored state.
- Added and validated `homeassistant-cli` on PiServ, using the existing private
  Hermes Home Assistant token and the remote REST API for full entity/service
  control. The Home Assistant Assist MCP remains available as a secondary path.
- Enabled Hermes to use the dedicated `hass-cli` wrapper as its primary
  Home Assistant control path while retaining the Assist MCP for secondary
  discovery and verification.
- Reconciled the fail-closed Hermes tool catalog with the deployed upstream
  catalog, explicitly denying the new `bfl` toolset and removing toolsets no
  longer exposed by the pinned Hermes revision. Catalog validation now scopes
  exact checks to built-in tools when Hermes also reports configured MCP
  servers.

## [0.4.0] - 2026-08-08

### Reliability

- Added a reversible PiServ cold-reset policy that validates distinct private
  rollback and runtime-control paths, reconciles one final `reboot=c` token,
  activates the running kernel's cold mode, and supports returning to the
  Raspberry Pi device-tree default without automatic reboot.
- Validated the cold policy through its activation and three subsequent
  persistent reboots; all returned with NVMe mounts and critical services
  healthy, bringing the observed cold-reset series to nine successes.
- Rendered a separate Freenove background task-manager artifact that fixes the
  upstream SIGTERM handler without dirtying the pinned source tree, restarts the
  managed service only when needed, preserves it when an existing unit is
  unmanaged, and exits cleanly during system shutdown.
- Added a pre-network-teardown shutdown email with bounded, authenticated
  journal correlation for nearby `sudo` evidence.
- Retried boot notification delivery only for bounded temporary mail failures,
  avoiding a boot-time DNS race by using the local hostname without a DNS lookup
  and preserving permanent SMTP errors as visible systemd failures. The generated
  systemd start timeout now covers the full retry budget, and negative policy
  tests fail when validation is bypassed.
- Added an Ansible-managed Wi-Fi connectivity watchdog that checks the WLAN
  link, gateway, and DNS, then escalates from connection restart to
  NetworkManager restart. Host reboot escalation is opt-in.
- Configured PiServ to reboot after 15 continuous minutes without a route to
  either public internet probe, while preventing a Wi-Fi outage from rebooting
  a host that remains online through another IPv4 default-route interface.
- Required PiServ's locally configured Wi-Fi profile for deterministic recovery
  and required the active cold reboot mode immediately before automatic reboot.
- Extracted the watchdog into the reusable `wifi_watchdog` role with
  Galaxy-ready metadata, standalone documentation, tests, and release guidance.
- Included the Wi-Fi watchdog in the canonical full-host convergence entry
  point and bound its default gateway probe to the monitored Wi-Fi interface.
- Hardened the reusable watchdog against localized `nmcli` state, configured
  profile fallback, wall-clock changes during recovery, mismatched systemd
  service-path overrides, and DNS success delivered through another network
  interface.
- Retried failed connection activations and NetworkManager restarts while an
  outage continues without blocking higher recovery levels, and retried the
  connection after a successful NetworkManager restart.
- Made privileged path inspection authoritative and preserved fresh-host
  check-mode convergence when the watchdog unit is not created yet, including
  handler execution.
- Corrected the PiServ watchdog runbook to verify service state on PiServ
  rather than the Ansible controller.
- Made a DNS resolver failure fail the watchdog health check explicitly.
- Preserved fresh check-mode convergence for missing parent directories and
  constrained watchdog unit paths to systemd's system unit directory.
- Restricted the root-executed watchdog script to a validated trusted system
  path.

### Cgroup Memory Controller

- Extracted managed cgroup-memory boot policy into a Galaxy-ready local
  `cgroup_memory_controller` role, keeping PiServ artifact identities and
  runtime policy exclusively in the consumer configuration.
- Added a full managed copy of the Raspberry Pi vendor DTB that removes exactly
  `cgroup_disable=memory` with `fdtput`, validates the result with `fdtget`, and
  is selected through a marked `device_tree=piserv-cgroup-memory.dtb` entry.
- Preserved the vendor DTB while retaining initial boot-artifact backups,
  explicit rollback, and refresh after vendor DTB updates.
- Activated the controller after an approved reboot and verified `memory` in
  the live cgroup v2 controller list before testing enforced model-service
  limits.

### Hermes Agent

- Made installer, inference-plugin, and backup-storage ownership checks fail
  before package, identity, download, or service mutations, preserving foreign
  destinations instead of overwriting them.
- Updated Nous Hermes Agent to the pinned upstream `v2026.8.3` release
  (`0.20.0`) under a root-owned code path and an unprivileged `hermes-agent`
  runtime identity.
- Configured `gpt-5.6-luna` as the default Codex provider with tested Spark,
  Terra, and Sol fallback order, bounded reasoning-effort overrides, and
  session-scoped Terra and Sol selectors.
- Added a managed Hermes provenance plugin, validated it with a live Luna
  response, and stored only private, content-free inference audit metadata.
- Added an official Home Assistant MCP gateway configuration that reads its
  dedicated token only from a private runtime environment file, then validated
  authenticated tool discovery plus an end-to-end Hermes state read and
  reversible four-second light on/off operation.
- Installed the checksum-verified official Codex CLI `0.145.0` Linux ARM64
  release, completed ChatGPT device authorization for both Codex CLI and
  Hermes, and validated direct and Hermes-mediated responses without an API key.
- Limited Hermes to memory and skill tools with write approval while explicitly
  disabling terminal, filesystem, browser, code execution, Home Assistant, and
  all other bundled toolsets.
- Added a hardened Hermes dashboard with native password authentication,
  scrypt-only runtime state, a root-only generated-password proposal,
  source-scoped LAN UFW access, Tailnet ingress, and an SSH-tunnel recovery
  workflow.
- Built the dashboard chat terminal UI into a separate root-owned runtime
  artifact with a Hermes-revision marker, preventing the unprivileged
  dashboard service from attempting and failing `npm install` during chat
  startup and rebuilding it after a pinned-source update.
- Reduced the deployed dashboard production audit to one moderate transitive
  `undici` finding; it serves prebuilt assets through a Python service.
- Added daily full Hermes state backups to the external SSD with 30-day
  retention and validated the first live archive.
- Added the reusable `hermes_agent` Ansible role, PiServ playbook, live health
  assertions, one-command provider-login helper, runbook, and updated
  architecture track.
- Added checksum-pinned Gemma 4 E2B and Granite 3.3 2B local-model benchmarks
  through loopback-only llama.cpp systemd services, with 64K context,
  constrained KV cache, memory limits, integrity checks, and result capture.
- Moved reproducible local-model weights outside Hermes state backups and added
  an address-space cap that remains effective when a host disables cgroup memory.
- Added an isolated persistence verifier for a dashboard restart, Hermes
  backup/restore, reviewed local-skill discovery, and provider-transport
  migration to a bounded Granite loopback endpoint.
- Enabled cgroup v2 memory control and proved that guarded 64K full-provider
  tests for Gemma 4 E2B and Granite 3.3 2B exceed the 4 GB host's 1.5 GiB
  reserve. The guard stopped only the model service and preserved dashboard
  health, so PiServ now disables local-model deployment while retaining the
  reusable framework for future hardware.
- Validated a locally generated Llama 3.2 1B Instruct Q4_K_M artifact with a
  loopback-only 64K synthetic response test. It used about 1.50 GiB cgroup
  memory, produced the expected visible response in 1.2 seconds, and left the
  dashboard healthy; it is not yet the managed Hermes provider.
- Rejected Llama 3.2 1B Instruct as a local Hermes provider on the 4 GB host:
  its isolated 64K memory-and-skill proof left PiServ unreachable while
  processing the Hermes prompt, followed by an unclean boot recovery. Removed
  the temporary model deployment and retained Codex as the only provider.
- Kept the future local-model capability inert by default, required an active
  cgroup v2 memory controller before enabling it, and validated bounded memory
  and address-space settings before rendering its services.
- Formally accepted Home Assistant's Assist exposure policy as the authority
  for the broader MCP entity and operation surface used by Hermes.

## [0.3.0] - 2026-07-29

### PiServ Installation

- Prevent the Freenove I2C reboot task from executing during check-mode
  validation.
- Added the repeatable `scripts/run-piserv-install.sh` wrapper for ordered
  full-host convergence through `ansible/playbooks/piserv-install.yml` after
  manual Tailscale and pCloud bootstrap, while keeping destructive migration
  and operator-only health checks separate.
- Made the Tailscale wrapper safe in check mode by skipping an upstream role
  that parses command output Ansible does not produce in that mode, while
  retaining PiServ's read-only runtime probes.
- Added a read-only external-storage preflight before all mutating installation
  playbooks and documented every manual first-install prerequisite and the
  direct-IP SSH recovery preflight.

### External SSD Resilience

- Retained bounded systemd journals on the PiServ root NVMe filesystem so
  previous-boot power, USB, and filesystem evidence survives a reboot.
- Extracted journald configuration into a local Galaxy-ready role while keeping
  PiServ's persistent-storage and retention policy in its consumer playbook.
- Installed `smartmontools` in the base role and validated the dynamically
  discovered root NVMe SMART health.
- Added label-based external-storage discovery while retaining an ignored local
  model-and-serial identity check before the playbook mutates the resolved disk;
  bridge-aware SMART checks validate the verified parent disk.
- Added a read-only Linux helper that discovers the external USB disk identity
  and, when run on the Ansible controller, creates the ignored model-and-serial
  file only after explicit operator approval.
- Completed a bounded 4 GiB backup-directory write, checksum, direct-readback,
  cleanup, and fresh kernel-log validation with no new transport or filesystem
  errors.
- Captured the full read-only SMART baseline for the root NVMe and dynamically
  discovered external NVMe, including health, wear, temperature, power, and
  error-log fields.

### Jackett Search

- Pin PiServ's Jackett deployment to the published upstream `v0.3.0` release
  tag, whose Makefile manages the Linux-Docker FlareSolverr service URL and
  removes macOS `._*` metadata sidecars during Jackett installation.
- Adapt the role to the upstream standalone CLI runtime and leave Compose
  network declarations under upstream ownership.
- Re-run the applicable upstream component installation when its generated
  Compose file loses the required shared-network membership or declaration.
- Reinstall a missing or non-executable standalone runtime even when its
  launcher remains correct, and remove the runtime after partial launcher
  cleanup.
- Refuse recursive standalone-runtime cleanup without the expected managed
  executable, preserving unrelated directories at an overridden install path.
- Install `jq` through the base role's standard host-package step for JSON
  inspection and diagnostics.
- Reject tag, task-start, interactive-step, and Ansible tag-environment
  partial-execution controls through the full-install wrapper, and make its
  check-mode forwarding state flow into the firewall preflight.
- Make external-storage identity discovery emit redirectable YAML and install
  it with an atomic, mode-restricted write.

## 0.2.0 - 2026-07-28

### Ansible Maintainability

- Grouped adjacent playbook and role tasks behind named blocks when they share
  execution conditions, making check-mode, configuration-mode, and
  feature-specific branches visible without repeated task-level predicates.
- Made Freenove hardware apply reporting explicitly normal-mode-only so check
  mode does not parse output from its skipped hardware command.
- Deferred VNC selector enablement, socket probes, and output validation when
  check mode only predicts their units or service start, while reporting a
  pending output selection as changed.
- Deferred pCloud checkout, build, install, and mount-root probes when a fresh
  check-mode run only predicts their artifacts.
- Deferred RaiPlaySound command and user-timer probes when a fresh check-mode
  run only predicts their installed files.

### Jackett Search

- Replaced the project-owned Docker Compose deployment with a Galaxy-ready
  `jackett_search` role that uses the upstream Makefile for the CLI, Jackett,
  and FlareSolverr lifecycle.
- Pinned the PiServ jackett-search source revision for reproducible deployments.
- Kept the upstream Jackett and FlareSolverr `latest` image choices rather than
  defining project image pins.
- Restricted Docker-published TCP `9117` to the current IPv4 LAN and Tailnet
  through a persistent `DOCKER-USER` policy, because published Docker ports do
  not traverse UFW's normal input chain.
- Added the Jackett runbook with tracker-credential, update, validation, and
  recovery procedures.
- Stored generated Compose files, Jackett state, and API-backed CLI
  configuration in `admin`'s private `~/.config/jackett-search` directory.
- Kept create-only configuration preservation while loading its generated API
  key whenever live Jackett validation is enabled.

### External SSD Storage

- Repartitioned the verified ASM246X external disk as one GPT partition spanning
  3.64 TiB and formatted it as journaled ext4 labeled `external-data`.
- Added UUID-based mounting at `/mnt/external-data` with `nodev`, `nosuid`,
  and optional-device boot behavior, while destructive actions verify a local
  stable by-id device identity.
- Deferred post-mount paths, ACLs, and state probes when check mode only
  predicts a storage reconnect or mount-option change.
- Deferred group- and ACL-dependent storage work when a fresh check-mode run
  only predicts those prerequisites.
- Added the dedicated `external-data` group, shared ACL policy, restricted
  backup directory, and non-destructive convergence playbook.
- Added the external SSD storage decision record and operator runbook.

### Cockpit Extensions

- Added `cockpit-storaged` for external-disk inspection and emergency storage
  operations.
- Added `cockpit-sosreport` for operator diagnostic-report collection.
- Added `cockpit-packagekit` for interactive package inspection and emergency
  package actions while retaining Ansible as the normal source of truth.

### Cockpit Web Console

- Added the Cockpit HTTPS web console, socket activation, and a local login-page
  assertion to the PiServ base role.
- Kept the reusable base-role default minimal while the PiServ playbook adds
  Storage, SOSReport, and PackageKit extensions.
- Deferred Cockpit socket management when a fresh check-mode run only predicts
  package installation.
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
- Deferred package-dependent Glances configuration and probes on fresh
  check-mode runs while retaining them for converged hosts.
- Made Glances credential recovery rotate a missing hash or interrupted
  reconciliation only after authenticated validation, while preserving the
  active hash after the one-time bootstrap password is removed.
- Derived the Glances systemd override parent from its configurable destination,
  creating it only when absent and preserving existing system-directory
  metadata.
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
- Hardened VNC selector path validation, including rejecting every group- or
  other-writable parent mode, aligned its wait budget with the role timeout,
  and re-ran it after either vendor VNC service starts without restarting the
  current WayVNC process during deployment. Selector unit changes and missing
  installation links now reconcile both systemd links.
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
- Deferred post-apply Tailscale preference assertions when check mode reports
  policy drift that it cannot apply.
- Deferred PiServ preference management when a fresh check-mode run only
  predicts the Tailscale runtime installation.
- Ensured manual and auth-key first login apply the complete HA subnet-router
  policy.
- Added a Tailscale access runbook covering manual browser login, verification,
  diagnostics, recovery, route-approval and failover follow-up, key-expiry
  trade-offs, and firewall integration.
- Documented that PiServ keeps standard OpenSSH as the administration path and
  does not enable Tailscale SSH for now.

### VNC Client Validation

- Validated TigerVNC 1.16.2 from the operator Mac through the direct LAN,
  mDNS, and Tailscale endpoints, including certificate handling, `admin` PAM
  authentication, and the `DSI-1` desktop output.

### Firewall Policy

- Reaffirmed default-deny IPv6 LAN ingress and removed the deferred dual-stack
  management decision from the active TODO list; IPv6 Tailnet ingress remains
  governed by the existing `tailscale0` policy.
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
- Corrected the LAN mDNS rule to allow unicast UDP `5353` queries as well as
  multicast traffic, while removing UFW's unrestricted default mDNS pre-rules;
  macOS can send valid mDNS queries directly to PiServ's UDP `5353` address.
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
