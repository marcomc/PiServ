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

Before returning, the role also writes and verifies `cold` in
`/sys/kernel/reboot/mode`. This protects the first reboot after deployment;
changing the boot command line alone would affect only the next kernel. Ansible
never reboots the host automatically.

## Apply

```sh
ansible-playbook -i ansible/inventory.ini ansible/playbooks/piserv-base.yml
```

Before rebooting, verify active mode, boot configuration, and backup:

```sh
ssh admin@PiServ.local \
  'cat /sys/kernel/reboot/mode; sudo cat /boot/firmware/cmdline.txt; sudo ls -l /var/lib/piserv/reboot-policy/'
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
  tr -d "\000" </proc/device-tree/chosen/bootargs | tr " " "\n" | grep "^reboot=" | tail -n 1
  findmnt -n -o TARGET,SOURCE /
  findmnt -n -o TARGET,SOURCE /boot/firmware
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
override the mode and reboot. The current kernel remains in cold mode until
that reboot; the next kernel selects the device-tree default:

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

| Date | Command | Observed result | Follow-up |
| --- | --- | --- | --- |
| 2026-08-01 | `ANSIBLE_ROLES_PATH=.. ansible-playbook tests/test-reboot-mode.yml` | Applied `reboot=c`, removed it for `default`, preserved the original backup, and rejected four unsafe backup states | Retain focused lifecycle and fail-closed regressions |
| 2026-08-01 | `ANSIBLE_ROLES_PATH=.. ansible-playbook --check tests/test-reboot-mode-check.yml` | Predicted backup and cmdline changes without mutating fixtures | Keep the dedicated global check-mode entrypoint |
| 2026-08-01 | `printf 'warm\n' \| sudo tee /sys/kernel/reboot/mode`, then `ansible-playbook -i ansible/inventory.ini ansible/playbooks/piserv-base.yml` | Returned active mode to `cold`; recap `ok=133 changed=1 failed=0` | No reboot required for activation proof |
| 2026-08-01 | `sudo systemctl reboot` during activation and three persistent-policy trials | All returned in 33-40 seconds with mode `cold`, NVMe mounts intact, zero failed units, and Freenove active | Continue cold mode as production mitigation |
| 2026-08-01 | `ansible-playbook --check -i ansible/inventory.ini ansible/playbooks/piserv-base.yml` | Completed with `ok=129 changed=0 failed=0` | Treat the base policy as converged |
