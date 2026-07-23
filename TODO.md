# TODO

## Current

- Track upstream `Oefenweb/ansible-ufw` PR #54 and replace the fork commit pin
  with an upstream release after the change is merged and published.
- Approve PiServ's advertised subnet route in the Tailscale admin console and
  validate failover through the existing primary subnet router.
- Decide whether PiServ needs IPv6 LAN management access and, if so, add an
  explicitly scoped dual-stack UFW policy with live validation.
- When APT offers a WayVNC version newer than `0.9.1-1+rpt5`, run the
  three-restart acceptance test in the VNC runbook. Remove this item only if
  all restarts avoid `SIGSEGV`, `DSI-1` remains active, and VNC TCP is healthy.
- Validate TigerVNC 1.16.2 from this Mac to both direct PiServ LAN endpoints
  and the Tailscale `piserv` name. Confirm its certificate prompt, `admin` PAM
  authentication, and the `DSI-1` desktop, then record the outcome in the VNC
  runbook.
- Create an umbrella bootstrap playbook that orchestrates the existing base,
  Freenove, pCloud, mail, Home Assistant MQTT Agent, and other workload
  playbooks after their ordering is final.

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

- [ ] **Attach and prepare the 4 TB external SSD**
  - Assessment: ext4 is the preferred PiServ-owned filesystem; exFAT is the
    removable-media fallback for direct macOS/Linux access. APFS is not a
    suitable Linux service volume.
  - Proposal: [Google Drive and external storage](docs/tracks/google-drive-and-external-storage.md)
  - Actions:
    - Identify the enclosure, USB power behavior, device identity, and SMART
      support without formatting the disk before explicit approval.
    - Select ext4 for server ownership or exFAT for physical cross-platform use.
    - Configure a UUID-based mount, ownership, permissions, health checks, and
      recovery documentation.
    - Decide whether the volume needs encryption and Mac access through SMB or
      SFTP.
    - Validate reboot, disconnect, reconnect, filesystem checks, and sustained
      backup writes before using it for services.

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

- [ ] **Install Jackett Search and the Jackett service**
  - Assessment: Jackett documents ARM64 Linux support and a Docker deployment;
    the existing Jackett Search project should remain the operator-facing CLI.
  - Actions:
    - Locate and validate the existing Jackett Search project and its expected
      Docker image, volumes, ports, and configuration.
    - Install Docker prerequisites and deploy the pinned ARM64-compatible
      Jackett image with persistent state.
    - Configure tracker credentials outside Git, firewall the API, and validate
      search results and restart recovery.
    - Codify the deployment, update policy, health checks, and runbook in
      Ansible.

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

## Later

- Add Ethernet configuration notes when the server is connected by cable.
- Add backup and restore runbook.
- Add disaster recovery playbook.
- Add monitoring and alerting decisions.
- Add service-specific runbooks as workloads are deployed.
