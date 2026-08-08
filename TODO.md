# TODO

## Current

- [ ] **Validate automatic total-internet-outage recovery**
  - Assessment: PiServ's watchdog is configured to recover its locally
    configured NetworkManager profile and to request a cold reboot after 15
    minutes only when normal routing and every IPv4 default-route interface
    fail to reach either public probe. Its healthy-path deployment can be
    verified without risk; the actual outage path needs an approved alternate
    access route.
  - Actions:
    - With alternate access available, prove that a Wi-Fi-only outage does not
      reboot the host while another interface reaches a public probe.
    - Prove one controlled total-outage reboot, then validate Wi-Fi recovery,
      SSH, storage mounts, and the watchdog journal after the next boot.

- [ ] **Implement scheduled RTC wake-up**
  - Assessment: Raspberry Pi 5 provides `rtc0` through its built-in `rpi-rtc`.
    With continuous USB-C power, an RTC alarm can wake PiServ from a low-power
    halt at a scheduled time; this must not be confused with recovery after an
    external power loss.
  - Actions:
    - Add a managed, backed-up, and reversible EEPROM configuration for RTC
      wake-up, including `POWER_OFF_ON_HALT=1`.
    - Implement a systemd service and timer that sets `rtc0/wakealarm`, then
      performs a clean halt at the configured schedule.
    - Prove a short, operator-approved wake-up cycle before enabling a daily
      schedule; verify boot, SSH, storage mounts, and scheduled services.
    - Document the continuous-power requirement and recommend an RTC battery
      where time must survive a complete USB-C power loss.

- Track upstream `Oefenweb/ansible-ufw` PR #54 and replace the fork commit pin
  with an upstream release after the change is merged and published.
- When APT offers a WayVNC version newer than `0.9.1-1+rpt5`, run the
  three-restart acceptance test in the VNC runbook. Remove this item only if
  all restarts avoid `SIGSEGV`, `DSI-1` remains active, and VNC TCP is healthy.
- [ ] Validate the managed shutdown email notification path and confirm that a planned
  `sudo systemctl reboot` sends a message with the command, requesting user,
  and UTC request time before the network is stopped.
- [ ] Reinstate Hermes Agent role CI in the dedicated standalone role repository,
  and keep the role local workflow intentionally disabled in PiServ until that
  repository owns the long-term CI matrix.
- [ ] Add a CI target that executes the dedicated `wifi_watchdog` test harness
  (`ansible/roles/wifi_watchdog/tests/test-watchdog.sh`) so it is enforced during
  merges and does not regress in isolation.
- [ ] Extend Hermes/cleanup regression coverage to assert side-effect boundaries
  (for example, daemon-reload and override teardown in the mock harness) before
  collapsing them back to no-op coverage.

## Propositions

- [ ] **Automate ASM246X USB 3 link recovery before mount**
  - Priority: **High**
  - Assessment: The external ASM246X bridge can enumerate on the same physical
    Raspberry Pi USB 3 port at either `5000` or `480` Mbps. A bounded pre-mount
    gate can attempt one logical xHCI recovery without touching a mounted
    filesystem, then preserve availability by allowing a clearly reported
    degraded mount if the link remains at `480` Mbps.
  - Plan: [External SSD USB link recovery](docs/tracks/external-storage-usb-link-recovery.md)
  - Actions:
    - [ ] Implement a read-only link and device-identity classifier that runs
      after USB enumeration but before filesystem checks or mounting.
    - [ ] Implement one bounded, lock-protected recovery attempt with controller
      isolation, identity revalidation, timeouts, and bind restoration.
    - [ ] Gate both `systemd-fsck` and `/mnt/external-data` mounting on the
      preflight result while retaining the existing absent-disk `nofail` path.
    - [ ] Mount the verified device at `480` Mbps with a persistent warning when
      recovery fails or is refused for safety; block mounting on identity or
      layout mismatch.
    - [ ] Codify the helper, systemd ordering, policy variables, and disable path
      in Ansible without resetting USB during normal convergence or check mode.
    - [ ] Complete the validation matrix and staged live rollout, then update
      Decision 0017, the external-storage runbook, changelog, and this task.

- [ ] **Build Apple Home-compatible Python camera streaming service**
  - Assessment: A small Python stream service can expose the camera as MJPEG,
    HTTP, or RTSP, but Apple Home support needs a HomeKit-compatible path rather
    than assuming generic webcam streaming is enough.
  - Actions:
    - Identify the Pi camera hardware, driver stack, and supported capture
      pipeline on `PiServ.local`.
    - Prototype a Python streaming endpoint with predictable startup, health
      checks, and systemd logging.
    - Decide the Apple Home integration path: direct HomeKit camera support if
      feasible, or a documented bridge through an existing HomeKit-compatible
      camera bridge.
    - Keep Home Assistant integration out of scope unless it is requested later.
    - Add Ansible configuration and a runbook after the live prototype works.

- [ ] **Create Python web administration application**
  - Assessment: A local operator web app can centralize project status and safe
    operations, but it should start read-heavy and expose only explicit,
    audited controls.
  - Actions:
    - Define the first operator views: system health, managed services, storage,
      backup status, and recent logs.
    - Choose a minimal Python web stack that fits PiServ maintenance needs.
    - Add authentication, local-network exposure rules, and service hardening
      before enabling write actions.
    - Package the app as a systemd service and codify deployment in Ansible.
    - Document operator workflows in a runbook.

- [ ] **Refresh Hermes Agent dependency audit after the next upstream release**
  - Assessment: the locked-down Nous Hermes Agent runtime, Codex CLI, private
    dashboard, authenticated LAN/Tailnet access, persistent state, daily backup,
    Ansible deployment, and Home Assistant MCP path are live. The remaining
    framework maintenance item is the transitive `undici` dependency audit.
  - Proposal: [Hermes Agent framework research](docs/tracks/hermes-agent-framework-research.md)
  - Actions:
    - Reopen this task only when a new Hermes upstream release is selected,
      that release carries `undici >= 6.28.0`, or a new security finding
      requires earlier action. Then pin the release and repeat the production
      dependency audit before enabling it.

- [ ] **Complete Hermes smart-home control through Home Assistant and Apple Home**
  - Priority: **High**
  - Assessment: Hermes already reaches Home Assistant through the official MCP
    server and Assist exposure policy. The next release should stabilize this
    path and use Home Assistant's HomeKit Bridge as the preferred route to
    Apple Home and Siri.
  - Proposal: [Hermes Agent framework research](docs/tracks/hermes-agent-framework-research.md)
  - Actions:
    - Revalidate Hermes-to-Home Assistant MCP authentication, tool discovery,
      state reads, and reversible writes after service restart and backup
      restore.
    - Define and review the Home Assistant Assist exposure policy for the full
      desired operation surface; keep security-critical actions confirmation-
      gated even when activity-scoped autonomy is granted.
    - Configure and validate Home Assistant's HomeKit Bridge for the selected
      entities, then verify Apple Home and Siri reflect the resulting states.
    - Run the local acceptance harness from the Mac with an explicit allowlist,
      scoped state capture, post-write verification, cleanup, and audit report.
    - Resolve the current PiServ DNS/MCP reachability failure before marking
      this release task complete.
    - Keep direct Apple Home control through HomeClaw in a later release; use
      SSH or authenticated Tailnet Supergateway only after a separate decision.

- [ ] **Connect Hermes to Omar Shahine's HomeClaw MCP through SSH**
  - Proposal: [HomeClaw MCP over SSH](docs/tracks/homeclaw-mcp-over-ssh.md)
  - Use an authenticated SSH session from PiServ to run the HomeClaw MCP
    adapter as a stdio child while the HomeClaw macOS app is already running.
  - Keep the remote command and tool set explicitly allowlisted; do not expose
    an unrestricted shell to Hermes.
  - Validate read-only discovery first, then require confirmation and audit
    evidence for HomeKit writes and configuration changes.

- [ ] **Expose Omar Shahine's HomeClaw MCP through Supergateway on the Tailnet**
  - Proposal: [HomeClaw MCP with Supergateway](docs/tracks/homeclaw-mcp-supergateway.md)
  - Have an operator start a Supergateway relay on the Mac that converts the
    HomeClaw stdio MCP server to Streamable HTTP for PiServ.
  - Bind the relay to the Tailnet path only and add authentication, Tailscale
    ACLs, tool filtering, and write-operation auditing before enabling it.
  - Validate relay restart, Mac sleep/unavailability, read-only discovery, and
    confirmed HomeKit writes.

- [ ] **Define service-level cgroup v2 memory policy**
  - Assessment: Enabling the memory controller only makes memory accounting,
    pressure signals, and enforcement available. PiServ needs evidence-based
    policies for Hermes, local model servers, Docker workloads, and core
    services before `MemoryHigh`, `MemoryMax`, or swap limits are applied.
  - Actions:
    - After the controller is active, record baseline `memory.current`,
      `memory.events`, memory pressure, and restart behavior for each managed
      service under representative load.
    - Classify services into protected core services, bounded workloads, and
      burstable workloads; document the proposed `MemoryHigh`, `MemoryMax`,
      `MemorySwapMax`, and any required systemd slice hierarchy.
    - Implement approved systemd unit drop-ins and Docker/container limits in
      their owning Ansible roles, retaining `LimitAS` only where it remains a
      justified complementary guard.
    - Validate limit enforcement, OOM behavior, recovery, and continued SSH
      reachability before applying policies to additional services.

- [ ] **Instrument local-model freeze diagnostics**
  - Assessment: The 64K Llama full-provider proof ended with an unclean host
    stop while the model processed the Hermes prompt. Persistent PiServ logs
    contained no OOM, NVMe, PCIe, thermal, undervoltage, or kernel-panic record;
    the internal NVMe SMART log is healthy. A controlled retry needs independent
    controller-side telemetry to distinguish CPU or memory starvation, NVMe I/O
    faults, and a selective network failure from a complete host freeze.
  - Actions:
    - Create a controller-side monitor that writes timestamped reachability
      samples to the MacBook: ICMP, bounded SSH command, and dashboard HTTP
      health, without relying on `PiServ.local` mDNS.
    - Create a bounded PiServ-side collector with durable samples for cgroup
      `memory.current`, `memory.events`, `memory.swap.current`, PSI memory and
      I/O pressure, host RAM and swap, CPU load, temperature, `get_throttled`,
      NVMe `/proc/diskstats`, and service PID RSS.
    - Synchronize both clocks and record boot ID, kernel version, model unit
      limits, and test start and stop markers so post-reboot evidence can be
      correlated without assuming journal timestamps survived the failure.
    - Run one loopback-only, cgroup-contained local-model proof with the
      collector enabled and no concurrent model service; stop immediately on
      memory-limit events, sustained pressure, or lost controller-side health.
    - After any interruption, collect prior-boot journal, SMART and PCIe/NVMe
      errors, filesystem recovery records, watchdog evidence, and both telemetry
      logs before attempting another model run.
    - Document the result and only reconsider a local default provider after a
      complete proof, clean cleanup, and sustained SSH/dashboard availability.

- [ ] **Evaluate and deploy Google Drive access and synchronization**
  - Assessment: Google Drive for Desktop is unavailable on Linux. `rclone`
    provides the best current combination of ARM64 CLI access, FUSE mounting,
    filtered remotes, one-way backup, and controlled bidirectional `bisync`.
  - Proposal: [Google Drive and external storage](docs/tracks/google-drive-and-external-storage.md)
  - Actions:
    - Confirm the live PiServ OS, architecture, FUSE support, and available
      storage before selecting the deployment path.
    - Test a restricted Google Drive remote with OAuth scope, root folder, and
      filter settings appropriate for shared services.
    - Prototype a read-only/live FUSE mount and a separate Drive-to-SSD backup.
    - Evaluate `bisync` on a small test folder, including conflict and deletion
      recovery, before considering broader write access.
    - Codify credentials, systemd units, health checks, retention, and restore
      procedures in Ansible and runbooks.

- [ ] **Decide whether to encrypt the external SSD**
  - Assessment: Deferred until backup-data sensitivity, unattended unlock, and
    recovery requirements are defined.
  - Actions:
    - Decide whether LUKS2 encryption is required for the PiServ-hosted volume.
    - Document key storage, boot unlock, recovery, and restore implications.
    - Keep any encryption or migration path separate from steady-state storage
      convergence.

- [ ] **Build a complete daily GitHub account disaster backup**
  - Assessment: per-repository bare mirrors provide complete Git branches and
    tags; Git LFS and non-GitHub metadata require explicit additional handling.
  - Actions:
    - Inventory all MarcoMC repositories and accessible organization
      repositories through paginated GitHub API or `gh` discovery.
    - Reuse and improve the existing Backup CLI where it fits, with a
      least-privilege token and no credentials in the repository.
    - Maintain one mirror per repository with daily `fetch --prune`, tags,
      branches, and Git LFS object retrieval.
    - Decide whether to include issues, pull requests, releases, wikis, Actions
      artifacts, and repository metadata.
    - Add a systemd timer, failure summary, retention policy, and restore test.

- [ ] **Complete Jackett tracker validation**
  - Assessment: Jackett and the operator-facing Jackett Search CLI are deployed
    through the pinned upstream release; only tracker-specific validation
    remains.
  - Actions:
    - Configure tracker credentials outside Git, then validate search results
      and restart recovery.

- [ ] **Deploy a torrent client behind VPN Unlimited**
  - Assessment: A separate torrent container behind Gluetun provides a clear
    network boundary and kill switch. Gluetun documents VPN Unlimited via
    OpenVPN; WireGuard needs a custom-provider configuration and must be tested
    against the actual account.
  - Actions:
    - Choose and pin an ARM64 torrent client image with persistent downloads and
      configuration on the external SSD.
    - Confirm VPN Unlimited credentials, supported protocol, server selection,
      and whether inbound port forwarding is available.
    - Deploy the torrent client with Gluetun, LAN-only administration, DNS
      controls, and a tested kill switch.
    - Prove that torrent traffic stops when the VPN is unavailable and that the
      web UI is not exposed through the VPN tunnel.
    - Add Ansible, secrets handling, health checks, update/rollback policy, and
      an operational runbook.

- [ ] **Evaluate Pi Node deployment for PiServ or a supported external host**
  - Assessment: The official Linux package is currently `amd64` only, while
    PiServ is `arm64`; PiServ also has less than the documented minimum disk
    space. Native installation is therefore blocked until an ARM64 package is
    published or a supported external `amd64` host is selected.
  - Proposal: [Pi Node on PiServ investigation](docs/tracks/pi-node-on-piserv.md)
  - Actions:
    - Monitor the official Pi Node APT repository and Linux documentation for
      ARM64 support.
    - Do not run multiple nodes with the same Pi account; verify the current
      account-to-node policy before any migration.
    - If using an external host, validate Docker, Compose v2, 4 vCPUs, 4 GB RAM,
      300 GB durable storage, router port forwarding, and headless CLI operation.
    - Keep node private keys, PostgreSQL credentials, and Docker volumes outside
      tracked repository files.
    - Add Ansible and an operational runbook only after a supported target is
      selected and live installation succeeds.

## Later

- Export the local `journald` role to a standalone public repository and
  publish the first `marcomc.journald` Galaxy release when that distribution is
  required.
- Add Ethernet configuration notes when the server is connected by cable.
- Add backup and restore runbook.
- Add disaster recovery playbook.
- Add monitoring and alerting decisions.
- Add service-specific runbooks as workloads are deployed.
