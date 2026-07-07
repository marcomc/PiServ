# TODO

## Current

- Capture OS, kernel, firmware, package, storage, and network baseline.
- Document Wi-Fi configuration and current network path.
- Inventory enabled services and open listening sockets.
- Decide base security posture for SSH, firewall, updates, and user access.
- Decide the pCloud remote folder for `raiplaysound-cli` podcast media.
- Build and test the official `pcloudcc` console client on PiServ.
- Validate `pcloudcc` systemd startup and mount health on PiServ.
- Define pCloud credential storage for Ansible without committing secrets.
- Automate the validated `pcloudcc` setup.
- Verify Freenove FNK0100K first-boot behavior.
- Enable and validate I2C for the Freenove GPIO adapter and OLED.
- Decide whether the Freenove UI should run manually or as a managed service.
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
- Downloaded Freenove FNK0100 resources into `vendor/freenove/`.
- Documented the canonical local repository path.

## Later

- Add Ethernet configuration notes when the server is connected by cable.
- Add backup and restore runbook.
- Add disaster recovery playbook.
- Add monitoring and alerting decisions.
- Add service-specific runbooks as workloads are deployed.
