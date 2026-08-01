# Freenove FNK0100K Post-OS Runbook

## Purpose

Summarize the official Freenove FNK0100 tutorial steps that apply after the
case is assembled and Raspberry Pi OS is already running.

## Sources

| Source | Location |
| --- | --- |
| Local Freenove resources | `vendor/freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi-main/` |
| Freenove FNK0100 download page | <https://freenove.com/fnk0100> |
| Online tutorial | <https://docs.freenove.com/projects/fnk0100/en/latest/index.html> |
| Official GitHub repository | <https://github.com/Freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi> |
| Chapter 3: app control | <https://docs.freenove.com/projects/fnk0100/en/latest/fnk0100/codes/tutorial/3_APP_Control.html> |
| Chapter 4: speed test and PCIe Gen3 | <https://docs.freenove.com/projects/fnk0100/en/latest/fnk0100/codes/tutorial/4_Speed_Test_%26_PCIe_Gen3.0.html> |

## Kit Notes

FNK0100K is the variant with both the 4.3-inch DSI IPS screen and NVMe SSD.

The downloaded Freenove reference copy includes:

| Path | Purpose |
| --- | --- |
| `Tutorial.pdf` | Full Freenove case tutorial |
| `Installing Raspberry Pi OS.pdf` | Freenove OS install guide |
| `Code/` | Case-control Python application and tasks |
| `Picture/` | Product images |
| `Datasheet/MS51FB9AE.pdf` | GPIO adapter microcontroller datasheet |

## First Boot Checks

Before doing software setup, Freenove expects these case behaviors:

| Component | Expected behavior |
| --- | --- |
| Power supply | Official Raspberry Pi 5.1 V / 5 A adapter or equivalent |
| RGB lights | Rainbow mode |
| Case fans | Full speed for 3 seconds, then temperature-controlled mode |
| Screen | Off initially; expected before software setup |
| RPi STAT LED | Steady green after successful OS boot |
| Case PWR LEDs | Solid |
| Case STA LED | Flashes with SSD activity |

If RGB lights, fans, power LEDs, or SSD activity are abnormal, power off and
check GPIO adapter alignment, FPC cables, SSD cabling, and power connections
before continuing.

## Software Setup

Preferred automation:

```sh
ansible-playbook ansible/playbooks/freenove-post-os.yml
```

The playbook performs the required post-OS setup:

| Operation | Ansible behavior |
| --- | --- |
| Package index update | Uses `apt` cache refresh with a one-hour cache window |
| Freenove runtime packages | Installs Git, I2C tools, Python, OLED, PyQt, psutil, and SMBus packages |
| I2C enablement | Ensures `dtparam=i2c_arm=on` in `/boot/firmware/config.txt` |
| Reboot | Reboots only when I2C firmware changes, after verifying active cold mode |
| Freenove code | Copies the local vendored Freenove tree from the Ansible controller into `/opt/freenove/` |
| Freenove updates | Uses the pinned local vendor copy for PiServ; Git refreshes remain opt-in for the public role |
| Runtime config | Writes `Code/app_config.json` so LED, fan, and OLED startup behavior is reproducible |
| Expansion preflight | Requires Freenove controller detection before enabling the background service |
| Background service | Enables and starts `my_app_running.service` under the `admin` user |
| Hardware apply | Applies LED and fan config directly through Freenove's expansion-board API |
| Shutdown cleanup | Renders a validated SIGTERM-safe runtime artifact without changing upstream source |
| Launchers | Creates application-menu and desktop launchers for `FNK0100` |
| Validation | Checks `/dev/i2c-1`, Python imports, Freenove Python syntax, JSON config, and service state |

PiServ should not keep the old Freenove checkout in the `admin` home directory
after the controller-copy install has been applied. The active runtime copy is
owned by Ansible under `/opt/freenove/`.

Optional Freenove tutorial operations are exposed as explicit variables:

| Variable | Default | Effect |
| --- | --- | --- |
| `freenove_case_source_mode` | `controller_copy` in PiServ playbook | Copies local vendored Freenove files from the controller |
| `freenove_case_controller_src` | repo-local vendor path in PiServ playbook | Source tree copied to the Pi |
| `freenove_case_install_dir` | `/opt/freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi` in PiServ playbook | Target runtime path on PiServ |
| `freenove_case_manage_background_service` | `true` in PiServ playbook | Creates and manages `my_app_running.service` |
| `freenove_case_manage_sigterm_cleanup_fix` | `true` in PiServ playbook | Makes the upstream task manager clean up and exit on `SIGTERM` |
| `freenove_case_pre_reboot_mode` | `cold` in PiServ playbook | Requires active cold mode before an automatic I2C reboot |
| `freenove_case_validate_expansion_controller` | `true` in PiServ playbook | Fails closed when the Freenove I2C controller is not detected |
| `freenove_case_manage_app_config` | `true` in PiServ playbook | Manages `Code/app_config.json` |
| `freenove_case_apply_hardware_config` | `true` in PiServ playbook | Applies managed LED and fan values directly to the case controller |
| `freenove_case_led_task_enabled` | `false` in PiServ playbook | Keeps `task_led.py` from overriding Ansible-managed LED state |
| `freenove_case_led_mode` | `5` in PiServ playbook | Uses Freenove Close/off RGB mode |
| `freenove_case_led_red_value` | `0` in PiServ playbook | Clears the stored red component |
| `freenove_case_led_green_value` | `0` in PiServ playbook | Clears the stored green component |
| `freenove_case_led_blue_value` | `0` in PiServ playbook | Clears the stored blue component |
| `freenove_case_fan_task_enabled` | `false` in PiServ playbook | Keeps `task_fan.py` from overriding Ansible-managed fan state |
| `freenove_case_fan_mode` | `0` in PiServ playbook | Keeps Freenove case-controller automatic fan mode active |
| `freenove_case_fan_mode2_low_temp_threshold` | `40` in PiServ playbook | Raises the lower automatic fan threshold from the Freenove default |
| `freenove_case_fan_mode2_high_temp_threshold` | `65` in PiServ playbook | Aligns the upper automatic fan threshold with the PiGuard fan-on temperature |
| `freenove_case_oled_task_enabled` | `true` in PiServ playbook | Runs `task_oled.py` through the background manager |
| `freenove_case_oled_screen*_display_time` | `5.0` seconds in PiServ playbook | Keeps each enabled OLED screen visible longer before rotation |
| `freenove_case_manage_touchscreen_idle` | `true` in PiServ playbook | Runs a user idle service for the 4.3-inch touchscreen backlight |
| `freenove_case_touchscreen_idle_seconds` | `120` in PiServ playbook | Dims the touchscreen after two minutes without local input |
| `freenove_case_touchscreen_idle_brightness` | `0` in PiServ playbook | Turns the touchscreen backlight off while idle |
| `freenove_case_touchscreen_active_brightness` | `255` in PiServ playbook | Restores full touchscreen backlight brightness on input |
| `freenove_case_repo_update` | `false` | Fetches updates for an existing Freenove checkout |
| `freenove_case_install_pibenchmarks` | `false` | Clones the PiBenchmarks repository |
| `freenove_case_run_pibenchmarks` | `false` | Runs the storage benchmark once with a marker file |
| `freenove_case_manage_pcie_gen3` | `false` | Manages the PCIe Gen3 config line |
| `freenove_case_enable_pcie_gen3` | `false` | Enables Gen3 when PCIe management is opted in |

The upstream task manager calls a non-existent `stop_all_tasks()` method from
its `SIGTERM` handler. This was observed during a shutdown that did not return
PiServ to an online state. The role leaves upstream `task_manager.py` unchanged
and atomically renders `task_manager_ansible.py` with the existing
`stop_monitoring()` cleanup, no obsolete `atexit` callback, and a normal exit.
The systemd unit runs the managed artifact and restarts only when the artifact
or unit changes. Stopping the service validates this path; firmware reset
validation remains separate.

## 2026-08-01 Remediation Validation

| Command | Observed result | Follow-up |
| --- | --- | --- |
| `ansible-playbook -i ansible/inventory.ini ansible/playbooks/freenove-post-os.yml -e freenove_case_controller_src=<pinned-source>` | Restored pristine upstream source, rendered the managed artifact, changed the unit, and replaced PID `834` with `35383`; `failed=0` | Keep upstream source and managed runtime separate |
| Same playbook repeated | `ok=52 changed=0 failed=0`; PID remained `35383` | Treat controller copy, render, and service lifecycle as converged |
| `sudo systemctl stop my_app_running.service` followed by `systemctl show` | `Result=success`, `ExecMainStatus=0`, `ActiveState=inactive`; no warning journal entries | Preserve the real SIGTERM stop regression |
| `sudo systemctl start my_app_running.service` | Service returned active with PID `36940` | No reboot was performed during remediation |

Manual upstream steps from the tutorial are retained below for reference.

Run package index update:

```sh
sudo apt update
```

Install the OLED dependency:

```sh
sudo apt install python3-luma.oled
```

Enable I2C:

```sh
sudo raspi-config
```

In `raspi-config`, enable `Interface Options` -> `I2C`.

Copy or clone the Freenove case repository onto PiServ when live setup begins.
The upstream command is:

```sh
cd
git clone https://github.com/Freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi.git
```

Create the desktop launcher:

```sh
cd ~/Freenove_Computer_Case_Kit_for_Raspberry_Pi/Code/
sudo python create_desktop_shortcut.py
```

The generated launcher runs `Code/run_app.sh`, which changes into the `Code`
directory and starts the Freenove UI with:

```sh
sudo python app_ui.py
```

## Case Control Software

The Freenove UI controls and displays:

| Area | Function |
| --- | --- |
| Dashboard | CPU, RAM, CPU temperature, case temperature, storage, PWM values |
| LED | Rainbow, breathing, follow, manual, close, and custom modes |
| Fan | Follow-case temperature mode, manual PWM, and custom Python task |
| OLED | Time, usage, temperature, fan PWM display order and timing |
| Settings | UI rotation, task editing/testing, and startup service management |

Default OLED cycle: time, usage, temperature, fan.

Default fan thresholds in follow-case mode:

| Phase | Temperature | PWM |
| --- | --- | --- |
| Heating | `>= 30 C` | `100` |
| Heating | `>= 50 C` | `175` |
| Cooling | `< 50 C` | `100` |
| Cooling | `27 C <= temp < 30 C` | `75` |
| Cooling | `< 27 C` | stopped |

## PiServ Cautions

Do not blindly apply these tutorial suggestions on PiServ:

| Tutorial item | PiServ handling |
| --- | --- |
| `sudo chmod 777 ~/Desktop/Freenove.desktop` | Avoid unless a desktop-only issue proves it is needed |
| Disable sudo password through `raspi-config` | Decide explicitly before changing production sudo posture |
| Create Freenove background service from UI | Avoid; Ansible owns the service and runtime config |
| Edit `task_led.py`, `task_fan.py`, or `task_oled.py` | Back up or vendor upstream code before local changes |
| Enable `task_led.py` or `task_fan.py` for normal operation | Avoid unless you want Freenove's custom/demo loops to override Ansible-applied LED or fan values |

If the background-service preflight fails, check that the FNK0100 GPIO adapter
is seated correctly and visible on I2C address `0x21` before trying to start
`my_app_running.service`.

If bus 1 reports `SDA stuck at low`, isolate I2C devices on the GPIO adapter.
On PiServ, disconnecting the small OLED module cable released SDA and exposed
the FNK0100 controller at `0x21`, so the OLED module/cable path is the current
suspect.

PiServ's blue fan LEDs stayed on during a live 20-second hardware test with
Freenove fan mode `0` and duty `[0,0]`. The FNK0100 API exposes case RGB
control and fan PWM control, but no fan-LED-only control. Treat the blue fan
LEDs as powered by the fan hardware path, not by `freenove_case_led_*`.

The 4.3-inch DSI touchscreen exposes a Linux backlight device at
`/sys/class/backlight/10-0045`. PiServ uses an Ansible-managed user `swayidle`
service to set that backlight to `0` after 120 seconds of local input
inactivity and restore brightness to `255` on input resume.

The small OLED is an SSD1306 monochrome display driven through a 1-bit image
buffer. Its visible color cannot be changed to amber in software; amber would
require replacing the OLED module with an amber physical variant.

## Optional SSD Speed Test

Freenove suggests PiBenchmarks for NVMe speed testing:

```sh
git clone https://github.com/TheRemote/PiBenchmarks
cd PiBenchmarks/
chmod +x Storage.sh
sudo ./Storage.sh ~/
```

Use this as an optional benchmark, not as a prerequisite for basic case setup.

## Optional PCIe Gen3

Freenove documents PCIe Gen3 as experimental and recommends PCIe Gen2 for
stability. Leave PiServ on the default PCIe mode unless live testing shows a
clear need and the SSD is stable.

To enable Gen3, add this line to `/boot/firmware/config.txt` and reboot:

```text
dtparam=pciex1_gen=3
```

To disable Gen3, remove that line and reboot.

## PiServ Next Actions

1. Verify first-boot case behavior directly.
2. Run a visual/touchscreen smoke test of the Freenove UI on the case display.
3. Confirm LED, fan, and OLED behavior while `my_app_running.service` is active.
4. Decide whether PiServ should ever opt in to PCIe Gen3.

## Cleanup Validation

The 2026-07-14 cleanup pass confirmed that software state is reproducible:

| Check | Result |
| --- | --- |
| Runtime checkout | Single managed copy under `/opt/freenove/` |
| Runtime user | `admin` |
| I2C controller | FNK0100 at `0x21` |
| OLED | Present at `0x3c` |
| Hardware reconciliation | `changed: false` with LED off and fan thresholds `[40, 65]` |
| Background service | Active with OLED task running |
| Touchscreen idle service | Active for `/sys/class/backlight/10-0045` |
| Blue fan LEDs | Still on; accepted as physical hardware behavior outside API control |

The remaining visual smoke test must be performed at the physical case. Do not
disconnect the OLED or fan wiring while PiServ is powered.

## Validation Log

| Date | Command | Result |
| --- | --- | --- |
| 2026-07-07 | `ansible-playbook ansible/playbooks/freenove-post-os.yml` | Applied setup; reboot was required after I2C enablement |
| 2026-07-07 | `ansible piserv -b -m ansible.builtin.reboot` | Rebooted PiServ and exposed `/dev/i2c-1` |
| 2026-07-07 | `ansible-playbook ansible/playbooks/freenove-post-os.yml` | Passed with `changed=0` |
| 2026-07-07 | `ansible-playbook ansible/playbooks/freenove-post-os.yml` | Passed repeat idempotence with `changed=0` |
| 2026-07-07 | `ansible-playbook ansible/playbooks/freenove-post-os.yml` | Passed after Galaxy role split with `ok=17 changed=0` |
| 2026-07-07 | `ansible-playbook ansible/playbooks/freenove-post-os.yml` | Passed after scoped task split with `ok=18 changed=0` |
| 2026-07-07 | `ansible-playbook ansible/playbooks/freenove-post-os.yml` | Switched PiServ to controller-copy install under `/opt/freenove/`; first run changed 5 tasks |
| 2026-07-07 | `ansible-playbook ansible/playbooks/freenove-post-os.yml` | Passed controller-copy repeat idempotence with `ok=23 changed=0` |
| 2026-07-07 | `ansible-playbook ansible/playbooks/freenove-post-os.yml` | Managed `app_config.json`; guarded background-service enablement failed because the Freenove controller was not detected |
| 2026-07-08 | `i2cdetect -y 1` and Freenove `Expansion()` probe after cable reseat | Touch/display I2C devices appeared, but Freenove GPIO-controller bus still timed out with SDA low |
| 2026-07-08 | `i2cdetect -y 1` and Freenove `Expansion()` probe with small OLED cable disconnected | SDA returned high; bus scan passed; FNK0100 controller detected at `0x21` with version `20250724_V1.1` |
| 2026-07-08 | `i2cdetect -y 1` and Freenove `Expansion()` probe after OLED cable reseat | SDA remained high; FNK0100 controller detected at `0x21`; OLED detected at `0x3c` |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Enabled and validated `my_app_running.service` with LED, fan, and OLED tasks running |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Passed repeat idempotence with `ok=31 changed=0` |
| 2026-07-07 | `ssh admin@PiServ.local` | Removed old home-directory Freenove checkout; verified launchers point to `/opt/freenove/` |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Applied direct hardware config; disabled LED and fan custom tasks; first run changed 4 tasks |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Passed direct hardware apply repeat idempotence with `ok=35 changed=0` |
| 2026-07-08 | Freenove hardware helper readback | Reported `led_mode=4`, `fan_mode=2`, `fan_threshold=[30, 50]`, and `changed=false` |
| 2026-07-08 | `pgrep -af task_.*\\.py` | Confirmed only `task_manager.py` and `task_oled.py` are running |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Applied LED Follow mode with blue RGB base color; first run changed 3 tasks |
| 2026-07-08 | Freenove hardware helper readback | Reported `led_mode=2` and `all_led_color=[0, 0, 255]` for each LED group |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Passed LED Follow mode repeat idempotence with `ok=35 changed=0` |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Applied automatic fan thresholds `[40, 65]`; first run changed 3 tasks |
| 2026-07-08 | Freenove controller readback | Reported `case_temp=44`, `fan_mode=2`, `fan_threshold=[40, 65]`, `fan_duty=[100, 100]`, and CPU temperature `57.1 C` |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Passed automatic fan-threshold repeat idempotence with `ok=35 changed=0` |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Applied blue Breathing LED mode and OLED `5.0` second screen timing; first run changed 2 tasks |
| 2026-07-08 | Freenove controller and app-config readback | Reported hardware `led_mode=3`, blue LED color, and all OLED screen `display_time` values at `5.0` seconds |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Passed Breathing LED/OLED timing repeat idempotence with `ok=35 changed=0` |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Applied very dim white Breathing LED color `8,8,8`; first run changed 3 tasks |
| 2026-07-08 | Freenove controller readback | Reported hardware `led_mode=3` and `all_led_color=[8, 8, 8]` for each LED group |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Passed very dim white LED repeat idempotence with `ok=35 changed=0` |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Applied LED Close/off mode; first corrected run changed 2 tasks |
| 2026-07-08 | Freenove controller readback | Reported hardware `led_mode=0` and `all_led_color=[0, 0, 0]` for each LED group |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Passed LED Close/off repeat idempotence with `ok=35 changed=0` |
| 2026-07-08 | 20-second Freenove fan-off hardware test | Fan mode `0` and duty `[0,0]` were applied, but the physical blue fan LEDs remained on; fan mode was restored to automatic mode `2` afterward |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Installed touchscreen idle user service with a 120-second timeout; first run changed 4 tasks |
| 2026-07-08 | `ansible-playbook ansible/playbooks/freenove-post-os.yml -e ansible_host=PiServ.local` | Passed touchscreen idle repeat idempotence with `ok=47 changed=0` |
| 2026-07-14 | `ansible-playbook -i ansible/inventory.ini ansible/playbooks/freenove-post-os.yml --start-at-task 'Wait before validating Freenove background service stability'` | Background service stability check passed with `ok=3 changed=0` under `admin` |
| 2026-07-14 | Freenove hardware helper with `--no-save-flash` | Readback matched the managed LED-off and fan-threshold state with `changed=false` |
| 2026-07-14 | `i2cdetect -y 1` | FNK0100 controller `0x21` and OLED `0x3c` both present |
| 2026-07-08 | Live touchscreen idle timeout test | Restarted the idle service, waited 125 seconds, observed backlight brightness `0`, restored brightness to `255`, and confirmed the service remained active |
| 2026-07-08 | Freenove OLED source readback | Confirmed the OLED uses `ssd1306` and a 1-bit image buffer, so amber is not software-configurable |
