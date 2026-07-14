# 0014: Freenove Hardware Cleanup State

## Status

Accepted and software-validated on 2026-07-14.

## Context

The FNK0100K case had three cleanup questions: stale software placement, an
intermittent small-OLED/I2C cable path, and blue fan LEDs that remained lit
after software LED and fan shutdown commands.

## Decision

| Area | Decision |
| --- | --- |
| Runtime files | Keep one Ansible-managed checkout under `/opt/freenove/`; keep user home directories free of old Freenove checkouts |
| I2C | Keep the current cable seating because the controller and OLED are both visible and the bus is healthy |
| Case RGB | Keep the Ansible-managed RGB mode closed/off |
| Fans | Keep Ansible-managed automatic fan mode with thresholds `40` and `65` degrees C |
| OLED | Keep the OLED task enabled with the existing five-second screen timing |
| Fan LEDs | Accept the always-on blue fan LEDs as a physical limitation; the FNK0100 API has no independent fan-LED control |

No steady-state task disconnects or deletes hardware cables. Any physical fan
LED modification must be performed with the Pi powered off and documented as a
hardware change.

## Validation

Live PiServ checks confirmed:

- I2C bus 1 reports the FNK0100 controller at `0x21` and the OLED at `0x3c`.
- The Freenove controller reports `FNK0100`, version `20250724_V1.1`, LED mode
  `0`, fan mode `2`, thresholds `[40, 65]`, and fan duty `[100, 100]`.
- The hardware reconciliation helper returned `changed: false`.
- `my_app_running.service` is active under `admin` with the OLED task running.
- No old Freenove checkout exists under `/home/admin`.
- The touchscreen idle service is active and controls
  `/sys/class/backlight/10-0045`.

Physical blue fan LED illumination remains expected and is outside software
control.
