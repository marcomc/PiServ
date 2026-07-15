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
- Create an umbrella bootstrap playbook that orchestrates the existing base,
  Freenove, pCloud, mail, and workload playbooks after their ordering is final.

## Propositions

- [ ] **Install Glances for system observability**
  - Assessment: Glances is a low-effort monitoring layer for live PiServ
    visibility, but it should be installed with explicit service exposure and
    firewall expectations instead of leaving another unaudited listener.
  - Actions:
    - Validate package availability and runtime behavior on `PiServ.local`.
    - Decide whether Glances should run CLI-only, web UI, API mode, or a
      systemd-managed service.
    - Document listening address, port, authentication model, and firewall
      implications.
    - Codify the final install and service configuration in Ansible.

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

## Later

- Add Ethernet configuration notes when the server is connected by cable.
- Add backup and restore runbook.
- Add disaster recovery playbook.
- Add monitoring and alerting decisions.
- Add service-specific runbooks as workloads are deployed.
