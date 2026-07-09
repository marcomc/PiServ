# Ansible Role: Freenove Case

Configure the Freenove FNK0100 computer case kit after Raspberry Pi OS has been
installed.

## Table of Contents

- [Purpose](#purpose)
- [Requirements](#requirements)
- [Installation](#installation)
- [Role Variables](#role-variables)
- [Example Playbook](#example-playbook)
- [Supported Platforms](#supported-platforms)
- [Behavior](#behavior)
- [Task Layout](#task-layout)
- [Validation](#validation)
- [Release Notes](#release-notes)
- [License](#license)
- [Support](#support)

## Purpose

This role automates the safe post-OS Freenove FNK0100 setup path:

- install runtime packages
- enable I2C
- clone Freenove's official case-control repository
- create desktop and application-menu launchers
- validate I2C, Python imports, and Freenove Python source syntax

Background service management, PiBenchmarks, and PCIe Gen3 are available as
explicit opt-ins because they affect runtime or boot behavior.

## Requirements

| Requirement | Value |
| --- | --- |
| Target hardware | Raspberry Pi 5 with Freenove FNK0100-family case |
| Target OS | Debian-family Raspberry Pi OS |
| Tested OS | Debian 13 / Raspberry Pi OS Trixie |
| Ansible | `ansible-core >= 2.15` |
| Privilege escalation | Required |
| Network | Target must reach GitHub and Debian package repositories |

The role assumes the Raspberry Pi firmware config file is
`/boot/firmware/config.txt`. Override `freenove_case_boot_config_path` if your
image uses a different path.

## Installation

After the role is published to Ansible Galaxy:

```sh
ansible-galaxy role install marcomc.freenove_case
```

Pinned install example:

```sh
ansible-galaxy role install marcomc.freenove_case,0.1.0
```

Standalone role syntax validation:

```sh
ansible-playbook --syntax-check tests/test.yml
```

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `freenove_case_install_user` | Remote user fact or `pi` fallback | User that owns the checkout and launchers |
| `freenove_case_install_dir` | `/opt/freenove-case` | Freenove runtime path |
| `freenove_case_source_mode` | `git` | Source mode: `git`, `controller_copy`, or `archive_url` |
| `freenove_case_repo_url` | Freenove GitHub repository | Upstream case software repository |
| `freenove_case_repo_version` | `main` | Freenove branch, tag, or commit |
| `freenove_case_repo_update` | `false` | Fetch and update existing checkout on each run |
| `freenove_case_controller_src` | `""` | Controller-side source path for `controller_copy` mode |
| `freenove_case_archive_url` | `""` | Remote archive URL for `archive_url` mode |
| `freenove_case_archive_extra_opts` | `[]` | Extra options passed to `unarchive` |
| `freenove_case_archive_creates` | `{{ freenove_case_install_dir }}/Code/app_ui.py` | Archive idempotence marker |
| `freenove_case_boot_config_path` | `/boot/firmware/config.txt` | Firmware config path |
| `freenove_case_apt_packages` | See `defaults/main.yml` | Debian packages to install |
| `freenove_case_manage_desktop_launcher` | `true` | Create FNK0100 desktop/menu launchers |
| `freenove_case_app_name` | `FNK0100` | Launcher name and icon basename |
| `freenove_case_app_comment` | Freenove case description | Launcher comment |
| `freenove_case_reboot_on_i2c_config_change` | `true` | Reboot after changing I2C firmware config |
| `freenove_case_reboot_timeout` | `600` | Reboot timeout in seconds |
| `freenove_case_i2c_device` | `/dev/i2c-1` | Expected I2C device |
| `freenove_case_manage_background_service` | `false` | Manage Freenove background task service |
| `freenove_case_service_name` | `my_app_running.service` | Background task service name |
| `freenove_case_service_enabled` | `true` | Enable background service at boot |
| `freenove_case_service_state` | `started` | Background service state |
| `freenove_case_validate_expansion_controller` | `{{ freenove_case_manage_background_service or freenove_case_apply_hardware_config }}` | Require Freenove controller detection before service or hardware management |
| `freenove_case_manage_app_config` | `{{ freenove_case_manage_background_service }}` | Manage Freenove `Code/app_config.json` |
| `freenove_case_apply_hardware_config` | `{{ freenove_case_manage_app_config }}` | Apply managed LED and fan config directly to the expansion board |
| `freenove_case_apply_hardware_save_flash` | `true` | Save changed hardware config to Freenove controller flash |
| `freenove_case_hardware_apply_script` | `{{ freenove_case_install_dir }}/Code/ansible_apply_hardware_config.py` | Target path for the hardware apply helper |
| `freenove_case_led_task_enabled` | `false` | Run the Freenove LED background task |
| `freenove_case_fan_task_enabled` | `false` | Run the Freenove fan background task |
| `freenove_case_oled_task_enabled` | `true` | Run the Freenove OLED background task |
| `freenove_case_led_mode` | `0` | Freenove LED mode value |
| `freenove_case_fan_mode` | `0` | Freenove fan mode value |
| `freenove_case_oled_screen1` | See `defaults/main.yml` | OLED date/time screen settings |
| `freenove_case_oled_screen2` | See `defaults/main.yml` | OLED usage screen settings |
| `freenove_case_oled_screen3` | See `defaults/main.yml` | OLED temperature screen settings |
| `freenove_case_oled_screen4` | See `defaults/main.yml` | OLED fan screen settings |
| `freenove_case_manage_touchscreen_idle` | `false` | Manage touchscreen idle backlight control |
| `freenove_case_touchscreen_idle_seconds` | `300` | Idle seconds before dimming the touchscreen |
| `freenove_case_touchscreen_active_brightness` | `255` | Brightness restored on input |
| `freenove_case_touchscreen_idle_brightness` | `0` | Brightness applied while idle |
| `freenove_case_touchscreen_backlight_device` | `""` | Touchscreen backlight device; required when touchscreen idle is enabled |
| `freenove_case_touchscreen_idle_enable_linger` | `true` | Enable linger for the touchscreen idle user service |
| `freenove_case_manage_pcie_gen3` | `false` | Manage PCIe Gen3 config |
| `freenove_case_enable_pcie_gen3` | `false` | Enable PCIe Gen3 when managed |
| `freenove_case_install_pibenchmarks` | `false` | Clone PiBenchmarks |
| `freenove_case_pibenchmarks_repo_url` | PiBenchmarks GitHub repository | Upstream benchmark repository |
| `freenove_case_pibenchmarks_dir` | `/home/{{ freenove_case_install_user }}/PiBenchmarks` | PiBenchmarks checkout path |
| `freenove_case_run_pibenchmarks` | `false` | Run storage benchmark once |
| `freenove_case_pibenchmarks_marker` | `/var/lib/freenove-case/pibenchmarks.done` | Benchmark one-shot marker |

## Example Playbook

```yaml
---
- name: Configure Freenove case
  hosts: raspberry_pi
  become: true
  roles:
    - role: marcomc.freenove_case
```

Enable the Freenove background service explicitly:

```yaml
---
- name: Configure Freenove case with background service
  hosts: raspberry_pi
  become: true
  roles:
    - role: marcomc.freenove_case
      vars:
        freenove_case_manage_background_service: true
        freenove_case_manage_app_config: true
        freenove_case_apply_hardware_config: true
        freenove_case_led_task_enabled: false
        freenove_case_fan_task_enabled: false
        freenove_case_oled_task_enabled: true
```

Install from a controller-managed local checkout instead of cloning on the
Raspberry Pi:

```yaml
---
- name: Configure Freenove case from controller files
  hosts: raspberry_pi
  become: true
  roles:
    - role: marcomc.freenove_case
      vars:
        freenove_case_source_mode: controller_copy
        freenove_case_controller_src: /path/to/Freenove_Computer_Case_Kit_for_Raspberry_Pi
        freenove_case_install_dir: /opt/freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi
```

## Supported Platforms

| Platform | Status |
| --- | --- |
| Debian 13 / Raspberry Pi OS Trixie on Raspberry Pi 5 | Tested |
| Debian 12 / Raspberry Pi OS Bookworm on Raspberry Pi 5 | Metadata-supported, not yet live-tested |

## Behavior

The role intentionally does not apply Freenove's permissive
`chmod 777 ~/Desktop/Freenove.desktop` suggestion. Launchers are installed with
mode `0755`.

PCIe Gen3 is disabled by default because Freenove documents it as experimental
and recommends PCIe Gen2 for stability.

PiBenchmarks is not run by default because it is a benchmark workflow, not a
required case setup step.

The default public role source mode is `git`, but Git updates are disabled by
default after the initial clone. This keeps repeat idempotence runs independent
from GitHub availability. Set `freenove_case_repo_update: true` when you
explicitly want to refresh upstream code.

Private or air-gapped deployments can use `controller_copy` so the Ansible
controller copies a pinned local Freenove checkout to the Raspberry Pi. This is
the preferred mode for pinned or private deployments.

When `freenove_case_manage_app_config` is enabled, the role owns
`Code/app_config.json`. This makes LED, fan, and OLED startup behavior
reproducible, but Freenove UI changes to those managed values will be
overwritten on the next Ansible run.

When `freenove_case_apply_hardware_config` is enabled, the role also calls
Freenove's Python expansion-board API directly after service management. This
applies LED mode/color, fan mode, manual fan duty, and fan temperature
thresholds without opening the desktop app. Custom `task_led.py` and
`task_fan.py` processes can still override those values while they are running,
so keep `freenove_case_led_task_enabled` and
`freenove_case_fan_task_enabled` disabled for deterministic Ansible-managed
LED and fan behavior. LED mode `5` maps to Freenove Close/off mode and also
clears all stored RGB groups to `0,0,0`.

On FNK0100 hardware, the Freenove API does not expose a separate fan-LED
control. If illuminated fan LEDs remain on after RGB mode `5` and fan mode `3`
or hardware fan mode `0`, they are outside this role's software control.

When `freenove_case_manage_touchscreen_idle` is enabled, the role installs a
user `swayidle` service that dims the Linux backlight device after the configured
idle timeout and restores brightness when input resumes. This controls the
4.3-inch DSI touchscreen backlight, not the small OLED.

The small OLED is driven as an SSD1306 monochrome display with a 1-bit image
buffer. Its visible color is a property of the physical OLED module, not a
software setting.

When background service management is enabled, the role probes the Freenove
expansion controller before enabling the service. If the controller is not
detected, the role fails before starting a systemd restart loop.

## Task Layout

`tasks/main.yml` is only an orchestrator. Scoped operations live in dedicated
task files:

| File | Scope |
| --- | --- |
| `validate-target.yml` | Platform assertion |
| `packages.yml` | Runtime packages and hardware groups |
| `i2c.yml` | I2C firmware/module setup |
| `freenove-code.yml` | Freenove upstream checkout |
| `app-config.yml` | Optional Freenove runtime configuration |
| `expansion-controller.yml` | Optional Freenove controller preflight |
| `desktop-launchers.yml` | Application and desktop launchers |
| `background-service.yml` | Optional systemd service |
| `hardware-config.yml` | Optional direct hardware config apply |
| `touchscreen-idle.yml` | Optional touchscreen idle backlight service |
| `pcie-gen3.yml` | Optional PCIe Gen3 firmware setting |
| `pibenchmarks.yml` | Optional benchmark repository and one-shot run |
| `validate-runtime.yml` | Runtime validation |

## Validation

Role validation:

```sh
ansible-playbook --syntax-check tests/test.yml
ansible-lint .
```

Role validation after Galaxy-style export:

```sh
ansible-playbook --syntax-check tests/test.yml
ansible-lint .
```

Live idempotence validation used during development:

```text
ansible-playbook site.yml
ansible-playbook site.yml
```

The second run should report `changed=0`.

## Release Notes

See [CHANGELOG.md](CHANGELOG.md).

Publication steps are documented in [docs/releasing.md](docs/releasing.md).

## License

MIT. See [LICENSE](LICENSE).

This role clones Freenove's upstream repository but does not vendor or
redistribute Freenove source code in the Galaxy role package.

## Support

Use the repository issue tracker after the standalone public role repository is
created. Hardware-specific Freenove product issues should be directed to
Freenove support.
