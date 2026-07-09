# TODO

## Current

- Decide final user-account policy.
- Decide firewall policy after Tailscale is installed.
- Install Tailscale and include Tailscale clients in the firewall access model.
- Investigate VNC mirroring of the physical touchscreen session.
- Verify Freenove FNK0100K first-boot behavior.
- Fix or replace the small OLED module/cable path that pulls SDA low.
- Verify physical LED, fan, and OLED behavior under the managed Freenove service.
- Decide whether to accept, physically disconnect, or replace the always-on
  blue fan LEDs.
- Create an umbrella bootstrap playbook that orchestrates the existing base,
  Freenove, pCloud, mail, and workload playbooks after their ordering is final.

## Propositions

- [ ] **Install Glances for system observability**
  - Assessment: Glances is a low-effort monitoring layer for live PiServ
    visibility, but it should be installed with explicit service exposure and
    firewall expectations instead of leaving another unaudited listener.
  - Actions:
    - Validate package availability and runtime behavior on `piserv.example.com`.
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
      pipeline on `piserv.example.com`.
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

## Later

- Add Ethernet configuration notes when the server is connected by cable.
- Add backup and restore runbook.
- Add disaster recovery playbook.
- Add monitoring and alerting decisions.
- Add service-specific runbooks as workloads are deployed.
