# TODO

## Current

- Capture OS, kernel, firmware, package, storage, and network baseline.
- Document Wi-Fi configuration and current network path.
- Inventory enabled services and open listening sockets.
- Decide base security posture for SSH, firewall, updates, and user access.
- Build and test the official `pcloudcc` console client on PiServ.
- Validate EU-region pCloud login with source-built `pcloudcc` on PiServ.
- Validate `pcloudcc` systemd startup and mount health on PiServ.
- Validate `pcloudcc -s` saved credential location and permissions on PiServ.
- Automate the validated `pcloudcc` setup.
- Verify Freenove FNK0100K first-boot behavior.
- Fix or replace the small OLED module/cable path that pulls SDA low.
- Verify physical LED, fan, and OLED behavior under the managed Freenove service.
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

## Later

- Add Ethernet configuration notes when the server is connected by cable.
- Add backup and restore runbook.
- Add disaster recovery playbook.
- Add monitoring and alerting decisions.
- Add service-specific runbooks as workloads are deployed.
