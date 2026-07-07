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
| Create Freenove background service from UI | Inspect generated service first, then codify in Ansible |
| Edit `task_led.py`, `task_fan.py`, or `task_oled.py` | Back up or vendor upstream code before local changes |

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
2. SSH to PiServ and confirm OS, I2C status, OLED dependency, and NVMe layout.
3. Install only required packages and enable I2C.
4. Inspect Freenove service generation before enabling any boot-time service.
5. Convert the confirmed setup into Ansible.
