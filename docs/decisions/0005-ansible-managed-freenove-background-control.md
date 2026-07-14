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

Apply LED and fan settings directly through Freenove's Python expansion-board
API after service management. This makes Ansible the runtime apply path for LED
mode/color, fan mode, manual duty, and fan temperature thresholds.

Before service management, the role must verify that the Freenove expansion
controller is detected. If detection fails, the playbook fails before leaving a
systemd restart loop.

The PiServ playbook leaves Freenove's LED and fan demo/custom tasks disabled so
they do not overwrite Ansible-managed hardware state. OLED stays enabled
because the OLED display cycle is implemented by `task_oled.py`.

| Task | PiServ setting |
| --- | --- |
| LED | `freenove_case_led_task_enabled: false` |
| Fan | `freenove_case_fan_task_enabled: false` |
| OLED | `freenove_case_oled_task_enabled: true` |

## Consequences

- LED, fan, and OLED startup behavior is reproducible during recovery.
- LED and fan hardware values can be changed through Ansible variables without
  opening the Freenove desktop app.
- Freenove UI edits to managed config values are overwritten by the next
  Ansible run.
- The systemd service remains the runtime owner for OLED behavior.
- Service enablement is blocked until the Freenove I2C controller is visible.
- Physical behavior still needs visual and audible confirmation on the case.

## Validation

Validate with:

```sh
ansible-playbook ansible/playbooks/freenove-post-os.yml
ansible-playbook ansible/playbooks/freenove-post-os.yml
ssh admin@PiServ.local 'systemctl is-active my_app_running.service'
```
