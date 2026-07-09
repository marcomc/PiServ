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
- Create initial bootstrap playbook after live commands are validated.

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

## Done

- Verified SSH and non-interactive sudo through `operator@piserv.example.com`.
- Verified SSH through `operator@192.0.2.181`.
- Migrated PiServ boot and root filesystems from microSD to NVMe.
- Configured EEPROM boot order for NVMe first and microSD fallback.
- Confirmed NVMe root filesystem uses the available SSD capacity.
- Created initial Ansible inventory for PiServ.
- Added guarded NVMe migration shell automation.
- Added guarded NVMe migration Ansible playbook.
- Decided the pCloud podcast target path:
  `/mnt/pcloud/My Music/Podcasts/raiplaypodcast`.
- Downloaded Freenove FNK0100 resources into `vendor/freenove/`.
- Documented the canonical local repository path.
- Added and tested Freenove FNK0100K post-OS Ansible automation.
- Enabled and validated I2C for the Freenove GPIO adapter and OLED.
- Selected Ansible-managed Freenove background service and runtime config.
- Isolated Freenove controller detection failure to the small OLED module/cable
  path; the FNK0100 controller is detected when that cable is disconnected.
- Built and installed source-built `pcloudcc` on PiServ.
- Added a Galaxy-ready `pcloudcc` Ansible role and install playbook.
- Added and installed patched `pcloudcc` CLI TOTP prompt support.
- Validated patched `pcloudcc` TOTP credential bootstrap on PiServ.
- Validated pCloud FUSE mount and local podcast-target write/read/delete on
  PiServ.
- Validated `pcloudcc -s` saved credential location and permissions on PiServ.
- Added credential-free user-scoped `pcloudcc` systemd mount management.
- Validated `pcloudcc` systemd startup and saved-auth service restart on
  PiServ.
- Validated `pcloudcc` reboot recovery and mount health on PiServ.
- Confirmed pCloud write-test visibility from the Mac pCloud Drive path.
- Added repeatable `pcloudcc` health-check script and Ansible playbook.
- Added a Galaxy-ready `raiplaysound_cli` Ansible role and PiServ daily-sync
  playbook.
- Added a Galaxy-ready local `msmtp` role inspired by
  `fauch922.ansible_msmtp_setup`.
- Moved package-only system mail support out of `base` and into the dedicated
  `msmtp` role.
- Applied system mail metadata hardening and installed the `msmtp-system`
  compatibility wrapper on PiServ.
- Validated SMTP provider server-info through the default system config and
  compatibility wrapper.
- Validated one intentional system mail delivery test through the `root` alias.
- Added RaiPlaySound email keys to the existing create-only PiServ config.
- Installed and validated `raiplaysound-cli-daily-sync` as a user-scoped
  systemd timer on PiServ.
- Accepted direct writes to the pCloud-backed podcast target for the scheduled
  RaiPlaySound workload.
- Captured OS, kernel, firmware, package, storage, and network baseline.
- Documented Wi-Fi configuration and current network path without storing the
  Wi-Fi PSK.
- Inventoried enabled services and open listening sockets.
- Applied SSH root-login hardening while preserving `operator` sudo SSH access.
- Disabled CUPS, `rpcbind`, and NFS block-mapper services.
- Enabled unattended upgrades and automatic reboots at `06:30`.
- Disabled cloud-init by marker file and disabled its systemd units.
- Codified base hardening in the `base` Ansible role and `piserv-base.yml`
  playbook.

## Later

- Add Ethernet configuration notes when the server is connected by cable.
- Add backup and restore runbook.
- Add disaster recovery playbook.
- Add monitoring and alerting decisions.
- Add service-specific runbooks as workloads are deployed.
