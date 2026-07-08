# TODO

## Current

- Capture OS, kernel, firmware, package, storage, and network baseline.
- Document Wi-Fi configuration and current network path.
- Inventory enabled services and open listening sockets.
- Decide base security posture for SSH, firewall, updates, and user access.
- Verify Freenove FNK0100K first-boot behavior.
- Fix or replace the small OLED module/cable path that pulls SDA low.
- Verify physical LED, fan, and OLED behavior under the managed Freenove service.
- Decide whether to accept, physically disconnect, or replace the always-on
  blue fan LEDs.
- Create initial bootstrap playbook after live commands are validated.

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
- Installed and validated `raiplaysound-cli-daily-sync` as a user-scoped
  systemd timer on PiServ.
- Accepted direct writes to the pCloud-backed podcast target for the scheduled
  RaiPlaySound workload.

## Later

- Add Ethernet configuration notes when the server is connected by cable.
- Add backup and restore runbook.
- Add disaster recovery playbook.
- Add monitoring and alerting decisions.
- Add service-specific runbooks as workloads are deployed.
- Before publishing `raiplaysound_cli`, move private bootstrap config defaults
  into inventory, group vars, or role examples.
