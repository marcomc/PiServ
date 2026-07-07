# 0005: Ansible-Managed Freenove Background Control

## Status

Accepted.

## Context

PiServ should use the Freenove FNK0100K case controls for LED, fan, and OLED
behavior without depending on hidden first-run defaults from the Freenove UI.
The upstream background manager reads `Code/app_config.json` and starts
`task_led.py`, `task_fan.py`, and `task_oled.py` when those tasks are enabled.

## Decision

Enable `my_app_running.service` through Ansible and make Ansible manage the
Freenove `Code/app_config.json` file for PiServ.

Before service management, the role must verify that the Freenove expansion
controller is detected. If detection fails, the playbook fails before leaving a
systemd restart loop.

The PiServ playbook enables all three Freenove background tasks:

| Task | PiServ setting |
| --- | --- |
| LED | `freenove_case_led_task_enabled: true` |
| Fan | `freenove_case_fan_task_enabled: true` |
| OLED | `freenove_case_oled_task_enabled: true` |

## Consequences

- LED, fan, and OLED startup behavior is reproducible during recovery.
- Freenove UI edits to managed config values are overwritten by the next
  Ansible run.
- The systemd service is the runtime owner for background hardware behavior.
- Service enablement is blocked until the Freenove I2C controller is visible.
- Physical behavior still needs visual and audible confirmation on the case.

## Validation

Validate with:

```sh
ansible-playbook ansible/playbooks/freenove-post-os.yml
ansible-playbook ansible/playbooks/freenove-post-os.yml
ssh operator@piserv.example.com 'systemctl is-active my_app_running.service'
```
