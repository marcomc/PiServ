# System Baseline and Inventory

## Table of Contents

- [Purpose](#purpose)
- [Snapshot](#snapshot)
- [System Baseline](#system-baseline)
- [Storage Baseline](#storage-baseline)
- [Network Baseline](#network-baseline)
- [Package Baseline](#package-baseline)
- [Service Inventory](#service-inventory)
- [Socket Inventory](#socket-inventory)
- [Security Inputs](#security-inputs)
- [Refresh Commands](#refresh-commands)
- [Follow-Up](#follow-up)

## Purpose

Capture the 2026-07-08 live operating baseline taken before the base hardening
pass. For the current hardened SSH, service, cloud-init, and unattended-upgrades
state, see [Base security hardening](base-security-hardening.md). For the
current ingress policy, see [UFW firewall policy](ufw-firewall-policy.md).

## Snapshot

| Item | Value |
| --- | --- |
| Captured | 2026-07-08 15:03 CEST |
| Hostname | `PiServ` |
| Access path | `admin@PiServ.local` |
| Hardware | Raspberry Pi 5 Model B Rev 1.0 |
| Architecture | `arm64` |
| Operating system | Debian GNU/Linux 13.5 `trixie` |
| Kernel | `6.18.34+rpt-rpi-2712` |
| Boot target | `graphical.target` |
| Runtime model | Local Wayland session with user services |
| Admin linger | `yes` |

No failed system or user units were reported at capture time.

## System Baseline

| Item | Observed value |
| --- | --- |
| Firmware | `086b83e3`, released 2026-05-26 |
| Bootloader | Up to date, default release channel |
| Under-voltage/throttle | `throttled=0x0` |
| Temperature | `55.4 C` |
| Memory | 4.0 GiB total, 3.3 GiB available |
| Swap | 2.0 GiB zram, unused |

## Storage Baseline

| Mount | Source | Type | Size | Used | Notes |
| --- | --- | --- | --- | --- | --- |
| `/` | `/dev/nvme0n1p2` | `ext4` | 117 GiB | 7.8 GiB | NVMe root, `rw,noatime` |
| `/boot/firmware` | `/dev/nvme0n1p1` | `vfat` | 511 MiB | 88 MiB | NVMe boot partition |
| `/mnt/pcloud` | `pCloud.fs` | `fuse` | 10 TiB | 6.7 TiB | pCloud virtual filesystem |

Detected block devices:

| Device | Model | Size | Role |
| --- | --- | --- | --- |
| `nvme0n1` | `SSD 128GB` | 119.2 GiB | Primary boot/root storage |
| `zram0` | zram | 2.0 GiB | Swap |

## Network Baseline

| Interface | State | Addressing | Notes |
| --- | --- | --- | --- |
| `wlan0` | Up | DHCP-assigned IPv4/24 plus IPv6 | Active path |
| `eth0` | Down/unavailable | None | Future wired path |
| `lo` | Up | `127.0.0.1/8`, `::1/128` | Loopback |

Routing and DNS:

| Item | Value |
| --- | --- |
| Default route | `192.0.2.1` via `wlan0` |
| IPv4 DNS | `192.0.2.1` |
| Active Wi-Fi connection | `netplan-wlan0-HoStello` |
| Network renderer | NetworkManager via netplan |

The Wi-Fi netplan file contains a PSK. Only redacted output should be copied
into documentation.

## Package Baseline

| Item | Value |
| --- | --- |
| Installed Debian packages | 1668 |
| Manually marked packages | 259 |

Key package and command versions:

| Component | Version |
| --- | --- |
| `base-files` | `13.8+deb13u5` |
| `systemd` | `257.13-1~deb13u1` |
| `openssh-server` | `1:10.0p1-7+deb13u4` |
| `network-manager` | `1.52.1-1+rpt4` |
| `netplan.io` | `1.1.2-7+rpt1` |
| `linux-image-rpi-2712` | `1:6.18.34-1+rpt1` |
| `raspi-firmware` | `1:1.20260521-3` |
| `rpi-eeprom` | `28.28-1` |
| `python3` | `3.13.5-1` |
| `git` | `1:2.47.3-0+deb13u1` |
| `ffmpeg` | `8:7.1.5-0+deb13u1+rpt1` |
| `yt-dlp` | `2025.04.30-1` |
| `pcloudcc` | `2.0.1` |
| `raiplaysound-cli` | `2.5.0` |

## Service Inventory

Enabled system services at the pre-hardening capture:

| Service | Notes |
| --- | --- |
| `ssh.service` | SSH access |
| `NetworkManager.service` | Network management |
| `wpa_supplicant.service` | Wi-Fi supplicant |
| `avahi-daemon.service` | mDNS for `.local` access |
| `bluetooth.service` | Bluetooth enabled |
| `cups.service` | Printing service enabled |
| `lightdm.service` | Local graphical login |
| `wayvnc.service` | VNC server enabled |
| `wayvnc-control.service` | VNC control service enabled |
| `rpcbind.service` | RPC portmapper enabled |
| `nfs-blkmap.service` | pNFS block layout mapper enabled |
| `my_app_running.service` | Freenove case background tasks |
| `cron.service` | Scheduled system jobs |
| `systemd-timesyncd.service` | Time sync |
| `rpi-eeprom-update.service` | EEPROM update service |
| `cloud-init*.service` | Cloud-init services enabled |

Enabled user services for `admin`:

| Service | Notes |
| --- | --- |
| `pcloudcc.service` | pCloud FUSE mount |
| `freenove-touchscreen-idle.service` | Touchscreen idle control |
| `pipewire.service` family | Local audio session |
| `gcr-ssh-agent.service` | User SSH agent |
| `gnome-keyring-daemon.service` | User keyring |
| `fbd-alert-slider.service` | Touch UI component |
| `filter-chain.service` | User session component |

Enabled user timer:

| Timer | Next run at capture |
| --- | --- |
| `raiplaysound-cli-daily-sync.timer` | 2026-07-09 08:01:20 CEST |

## Socket Inventory

Open listening sockets at the pre-hardening capture:

| Protocol | Bind | Process | Notes |
| --- | --- | --- | --- |
| TCP | `0.0.0.0:22`, `[::]:22` | `sshd` | SSH |
| TCP/UDP | `0.0.0.0:111`, `[::]:111` | `rpcbind` | RPC portmapper |
| TCP | `*:5900` | `wayvnc` | VNC |
| TCP | `0.0.0.0:41609` | `pcloudcc` | pCloud client listener |
| UDP | `0.0.0.0:42420` | `pcloudcc` | pCloud client listener |
| UDP | `*:5353` | `avahi-daemon` | mDNS |
| UDP | Dynamic high ports | `avahi-daemon` | mDNS support sockets |

Systemd socket units also expose local sockets for D-Bus, journald, udev, CUPS,
cloud-init hotplug, and hostnamed.

## Security Inputs

These were inputs for the base security-posture decision, not the current final
policy.

| Area | Current state |
| --- | --- |
| SSH password auth | Disabled |
| SSH keyboard-interactive auth | Disabled |
| SSH pubkey auth | Enabled |
| SSH root login | `without-password` |
| SSH X11 forwarding | Enabled |
| SSH TCP forwarding | Enabled |
| Local firewall | No `ufw` or `iptables`; empty nftables ruleset |
| Remote-access exposure | SSH and VNC listen on all interfaces |
| RPC exposure | `rpcbind` listens on all interfaces |

These values are historical. UFW was enabled on 2026-07-13 with default-deny
incoming and routed policies, explicit LAN SSH/VNC/mDNS rules, Tailscale
interface ingress, and direct Tailscale UDP.

## Refresh Commands

Use these commands to refresh the baseline without writing secrets to docs:

```sh
ssh admin@PiServ.local 'hostnamectl; uname -a; uptime -p'
ssh admin@PiServ.local 'cat /etc/os-release; vcgencmd version'
ssh admin@PiServ.local 'vcgencmd get_throttled; vcgencmd measure_temp'
ssh admin@PiServ.local 'lsblk -e7 -o NAME,MODEL,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS'
ssh admin@PiServ.local 'df -hT -x tmpfs -x devtmpfs; findmnt /'
ssh admin@PiServ.local 'ip -brief addr; ip route'
ssh admin@PiServ.local 'nmcli -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show wlan0'
ssh admin@PiServ.local 'dpkg-query -f "${binary:Package}\n" -W | wc -l'
ssh admin@PiServ.local 'apt-mark showmanual | wc -l'
ssh admin@PiServ.local 'systemctl list-unit-files --type=service --state=enabled,enabled-runtime --no-pager'
ssh admin@PiServ.local 'systemctl --user list-unit-files --type=service --state=enabled,enabled-runtime --no-pager'
ssh admin@PiServ.local 'sudo ss -tulpen'
ssh admin@PiServ.local 'sudo sshd -T'
ssh admin@PiServ.local 'sudo nft list ruleset'
```

For netplan files, redact PSKs before storing output:

```sh
ssh admin@PiServ.local 'sudo awk "{ if (\$1 == \"password:\") print \"            password: REDACTED\"; else print }" /etc/netplan/*.yaml'
```

## Follow-Up

- Refresh the inventory after major baseline changes.
- Keep the current ingress allowlist synchronized with new listening services.
- Validate whether VNC mirrors the physical touchscreen session.
