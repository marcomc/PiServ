# Kernel Reboot Policy

## Purpose

Keep PiServ on the Raspberry Pi `cold` reset path because repeated warm resets
intermittently completed shutdown without returning the NVMe-root host online.
Cold mode requests a broader platform reset; it does not remove input power.

The policy is a reversible reliability mitigation. It does not prove whether
the underlying fault is in PSCI reset handling, bootloader PCIe/NVMe
reinitialisation, or the Freenove hardware path.

## Managed State

The PiServ base playbook enables:

```yaml
base_manage_kernel_reboot_mode: true
base_kernel_reboot_mode: cold
```

The role removes earlier `reboot=` tokens from `/boot/firmware/cmdline.txt` and
appends one final `reboot=c`. It preserves the first pre-policy command line at:

```text
/var/lib/piserv/reboot-policy/cmdline.txt.pre-managed-mode
```

Ansible never reboots the host automatically after changing this file.

## Apply

```sh
ansible-playbook -i ansible/inventory.ini ansible/playbooks/piserv-base.yml
```

Before rebooting, verify the file and backup:

```sh
ssh admin@PiServ.local \
  'sudo cat /boot/firmware/cmdline.txt; sudo ls -l /var/lib/piserv/reboot-policy/'
```

Perform the controlled reboot:

```sh
ssh admin@PiServ.local 'sudo systemctl reboot'
```

## Verify

After the host returns:

```sh
ssh admin@PiServ.local '
  cat /sys/kernel/reboot/mode
  tr -d "\000" </proc/device-tree/chosen/bootargs | tr " " "\n" | grep "^reboot="
  findmnt -n -o TARGET,SOURCE / /boot/firmware
  systemctl is-system-running
'
```

Expected state:

- `/sys/kernel/reboot/mode` reports `cold`;
- the last effective reboot token is `reboot=c`;
- `/` and `/boot/firmware` remain on the expected NVMe partitions;
- SSH and required services return without physical intervention.

## Rollback

For a managed return to the Raspberry Pi device-tree default, temporarily
override the mode and reboot:

```sh
ansible-playbook -i ansible/inventory.ini ansible/playbooks/piserv-base.yml \
  -e base_kernel_reboot_mode=default
ssh admin@PiServ.local 'sudo systemctl reboot'
```

For an exact emergency restore of the first pre-policy command line:

```sh
ssh admin@PiServ.local \
  'sudo sh -c "cat /var/lib/piserv/reboot-policy/cmdline.txt.pre-managed-mode > /boot/firmware/cmdline.txt"'
```

Change the tracked playbook policy before the next normal convergence if the
rollback must remain persistent.

## Validation Log

| Date | Command | Observed result |
| --- | --- | --- |
| 2026-08-01 | Base-role cold/default test | Applied `reboot=c`, removed it for `default`, and preserved the original backup |
| 2026-08-01 | PiServ check-mode convergence | Predicted only the private backup artifacts and final `reboot=c` token |
| 2026-08-01 | PiServ cold-policy deployment | Created a `0600 root:root` stable backup and reconciled the boot command line |
| 2026-08-01 | Activation plus three persistent cold reboots | All returned in 33-40 seconds with mode `cold`, NVMe mounts intact, zero failed units, and Freenove active |
| 2026-08-01 | Repeat cold-policy convergence | Completed with `changed=0` |
