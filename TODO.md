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
- Deploy the managed shutdown email notification and validate that a planned
  `sudo systemctl reboot` sends a message with the command, requesting user,
  and UTC request time before the network is stopped.

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

- [ ] **Complete Hermes Agent provider and capability integration**
  - Assessment: the locked-down Nous Hermes Agent runtime, Codex CLI, private
    dashboard, persistent state, daily backup, and Ansible deployment are live.
    Codex authentication and isolated state/provider-transport persistence
    validation are complete; external capabilities remain incomplete.
  - Proposal: [Hermes Agent framework research](docs/tracks/hermes-agent-framework-research.md)
  - Actions:
    - On a future 8 GB-or-larger PiServ host, re-enable the retained local-model
      framework and repeat guarded 64K full-provider proofs for Gemma 4 E2B and
      Granite 3.3 2B. Both crossed the 1.5 GiB host-reserve guard on the current
      4 GB host and are not installed there.
    - On a future 8 GB-or-larger PiServ host, repeat the Llama 3.2 1B full
      Hermes provider proof with memory and skill loading. Its guarded 64K
      synthetic loopback test passed on the current 4 GB host, but the
      full-provider proof ended in an unclean host stop while processing the
      Hermes prompt, so it is not a managed or default provider.
    - Verify the prepared Home Assistant MCP capability gateway after supplying
      the Home Assistant URL, dedicated token, and permitted entity set.
    - Review the pinned dashboard's three production and eight total high
      severity npm audit findings before exposing it beyond loopback and its
      SSH tunnel.
    - Add authenticated Tailnet access only after defining the identity and
      firewall policy.

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
