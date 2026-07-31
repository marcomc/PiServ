# TODO

## Current

- [ ] **Enable the cgroup v2 memory controller**
  - Assessment: The PiServ-managed overlay, `config.txt` entry, initial boot
    artifact backup, and kernel post-install refresh hook are deployed and
    passed their offline DTB merge validation. They will take effect only after
    an operator-approved reboot. The current kernel still exposes
    `cgroup_disable=memory`, so systemd and Docker cannot yet enforce their
    configured memory controls. Hermes retains its `LimitAS` fallback.
  - Actions:
    - Schedule an operator-approved reboot, then verify `memory` appears in
      `cgroup.controllers`, Docker exposes `memory.events`, and all managed
      services recover normally.
    - Keep the Hermes `LimitAS` guard in place and record the observed memory
      overhead and service limits after the change.

- Track upstream `Oefenweb/ansible-ufw` PR #54 and replace the fork commit pin
  with an upstream release after the change is merged and published.
- When APT offers a WayVNC version newer than `0.9.1-1+rpt5`, run the
  three-restart acceptance test in the VNC runbook. Remove this item only if
  all restarts avoid `SIGSEGV`, `DSI-1` remains active, and VNC TCP is healthy.
- Deploy the managed shutdown email notification and validate that a planned
  `sudo systemctl reboot` sends a message with the command, requesting user,
  and UTC request time before the network is stopped.

## Propositions

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

- [ ] **Set up Hermes AI agent for Home Assistant integration**
  - Assessment: Hermes should be treated as a local-network service first, with
    explicit network exposure, authentication, and Home Assistant integration
    boundaries before it controls or observes home automations.
  - Actions:
    - Identify the Hermes runtime, deployment model, and hardware requirements
      suitable for PiServ.
    - Decide whether Hermes should run directly on PiServ or as an isolated
      service with a dedicated system user and systemd unit.
    - Define the Home Assistant connection method for an instance on the same
      network, including API endpoint, token storage, and allowed capabilities.
    - Document firewall, Tailscale, and local-network access expectations before
      exposing the service.
    - Codify the final install, configuration, and service health checks in
      Ansible after live validation.

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
